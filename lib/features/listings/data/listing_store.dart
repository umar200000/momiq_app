import 'dart:convert';
import '../../customer/data/customer_api.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HousingType { apartment, house }

enum ServiceType { boarding, homeVisit, personal }

enum PetType { dog, cat }

class CareLocation {
  const CareLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
  final double latitude;
  final double longitude;
  final String address;
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      address.trim().isNotEmpty &&
      address.runes.length <= 1000;
  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'address': address,
  };
  factory CareLocation.fromJson(Map<String, dynamic> json) => CareLocation(
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lon'] as num).toDouble(),
    address: json['address'] as String,
  );
}

class ServiceListing {
  ServiceListing({
    required this.type,
    required Set<PetType> pets,
    required this.dailyPrice,
    this.capacity,
    this.location,
    this.active = true,
  }) : pets = Set.unmodifiable(pets);
  final ServiceType type;
  final Set<PetType> pets;
  final int dailyPrice;
  final int? capacity;
  final CareLocation? location;
  final bool active;
  ServiceListing withActive(bool value) => ServiceListing(
    type: type,
    pets: pets,
    dailyPrice: dailyPrice,
    capacity: capacity,
    location: location,
    active: value,
  );
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'pets': pets.map((p) => p.name).toList(),
    'price': dailyPrice,
    'capacity': capacity,
    'location': location?.toJson(),
    'active': active,
  };
  factory ServiceListing.fromJson(Map<String, dynamic> json) => ServiceListing(
    type: ServiceType.values.byName(json['type'] as String),
    pets: (json['pets'] as List)
        .map((p) => PetType.values.byName(p as String))
        .toSet(),
    dailyPrice: json['price'] as int,
    capacity: json['capacity'] as int?,
    location: json['location'] == null
        ? null
        : CareLocation.fromJson(json['location'] as Map<String, dynamic>),
    active: json['active'] as bool,
  );
}

enum ListingProblem { pets, capacity, location, price, conflict, storage, busy }

class ListingException implements Exception {
  const ListingException(this.problem);
  final ListingProblem problem;
}

/// Authenticated listings are committed to the server before updating the UI.
class ListingStore extends ChangeNotifier {
  ListingStore({Future<SharedPreferences> Function()? preferences, this.api})
    : _preferences = preferences ?? SharedPreferences.getInstance;
  static final instance = ListingStore();
  int _epoch = 0;
  int _boundSession = CustomerApi.sessionVersion;
  bool _disposed = false;
  bool Function() _scope() {
    final epoch = _epoch, version = CustomerApi.sessionVersion;
    return () =>
        !_disposed &&
        epoch == _epoch &&
        version == _boundSession &&
        version == CustomerApi.sessionVersion;
  }

  void _check(bool Function() current) {
    if (!current()) throw const ListingException(ListingProblem.storage);
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  void resetSession() {
    if (_disposed) return;
    _epoch++;
    busy = false;
    _boundSession = CustomerApi.sessionVersion;
    _listings = {};
    _housing = HousingType.apartment;
    _loaded = false;
    _loading = null;
    _prefs = null;
    _revision = 0;
    _moderation = {};
    api = null;
    notifyListeners();
  }

  static const storageKey = 'momiq.services.v1';
  final Future<SharedPreferences> Function() _preferences;
  CustomerApi? api;
  Future<void>? _loading;
  bool _loaded = false;
  SharedPreferences? _prefs;
  HousingType _housing = HousingType.apartment;
  Map<ServiceType, ServiceListing> _listings = {};
  int _revision = 0;
  Map<String, dynamic> _moderation = {};
  String status(ServiceType type) =>
      _moderation[type.name]?['status'] as String? ?? 'draft';
  String reason(ServiceType type) =>
      _moderation[type.name]?['reason'] as String? ?? '';
  bool isTest(ServiceType type) => _moderation[type.name]?['testOnly'] == true;
  Map<String, String>? appealTarget(ServiceType type) {
    final target = _moderation[type.name]?['appealTarget'];
    return target is Map ? Map<String, String>.from(target) : null;
  }

  bool busy = false;
  HousingType get housing => _housing;
  int get maxCapacity => housing == HousingType.apartment ? 1 : 3;
  ServiceListing? operator [](ServiceType type) => _listings[type];

  Future<void> load({bool refresh = false}) {
    final current = _scope();
    _check(current);
    if (refresh && !busy) _loaded = false;
    if (_loaded) return Future<void>.value();
    if (_loading != null) return _loading!;
    late final Future<void> operation;
    operation = _read(current)
        .then((_) {
          _check(current);
          _loaded = true;
        })
        .whenComplete(() {
          if (identical(_loading, operation)) _loading = null;
        });
    return _loading = operation;
  }

  Future<void> _read(bool Function() current) async {
    final prefs = await _preferences();
    _check(current);
    if (api == null && CustomerApi.enabled) {
      final restored = await CustomerApi.restore();
      _check(current);
      api = restored;
      if (api == null) throw const ListingException(ListingProblem.storage);
    }
    _prefs = prefs;
    Map<String, dynamic> json;
    if (api != null) {
      json = await api!.request('GET', '/me/listings');
      _check(current);
      // Legacy drafts belong to the current login (logout clears this key).
      // Keep them editable until the user explicitly saves them to the server.
      final legacy = _prefs!.getString(storageKey);
      if ((json['listings'] as List).isEmpty && legacy != null) {
        json = {
          ...jsonDecode(legacy) as Map<String, dynamic>,
          '_revision': json['_revision'],
          'moderation': json['moderation'],
        };
      }
    } else {
      final raw = _prefs!.getString(storageKey);
      if (raw == null) return;
      json = jsonDecode(raw) as Map<String, dynamic>;
    }
    _apply(json);
    notifyListeners();
  }

  void _apply(Map<String, dynamic> json) {
    final housing = HousingType.values.byName(json['housing'] as String);
    final listings = (json['listings'] as List).map(
      (e) => ServiceListing.fromJson(e as Map<String, dynamic>),
    );
    final restored = {for (final listing in listings) listing.type: listing};
    for (final listing in restored.values) {
      if (_validate(listing, housing) != null) {
        throw const FormatException('Invalid listing data');
      }
    }
    if (restored[ServiceType.personal]?.active == true &&
        restored.values.any(
          (e) => e.type != ServiceType.personal && e.active,
        )) {
      throw const FormatException('Conflicting active services');
    }
    _housing = housing;
    _listings = restored;
    _revision = json['_revision'] as int? ?? 0;
    _moderation = Map<String, dynamic>.from(json['moderation'] as Map? ?? {});
  }

  List<ServiceListing> conflictsFor(ServiceType type) => _listings.values
      .where(
        (e) =>
            e.active &&
            e.type != type &&
            (type == ServiceType.personal || e.type == ServiceType.personal),
      )
      .toList();

  ListingProblem? validate(ServiceListing value) =>
      _validate(value, housing) ??
      (value.active && conflictsFor(value.type).isNotEmpty
          ? ListingProblem.conflict
          : null);

  static ListingProblem? _validate(ServiceListing value, HousingType housing) {
    if (value.pets.isEmpty ||
        (value.type != ServiceType.homeVisit && value.pets.length != 1)) {
      return ListingProblem.pets;
    }
    if (value.dailyPrice <= 0 || value.dailyPrice > 999999999) {
      return ListingProblem.price;
    }
    if (value.type == ServiceType.boarding &&
        (value.capacity == null ||
            value.capacity! < 1 ||
            value.capacity! > (housing == HousingType.apartment ? 1 : 3))) {
      return ListingProblem.capacity;
    }
    if ((value.location != null && !value.location!.isValid) ||
        (value.type != ServiceType.homeVisit && value.location == null)) {
      return ListingProblem.location;
    }
    return null;
  }

  Future<void> save(ServiceListing value) async {
    final current = _scope();
    await load();
    _check(current);
    final problem = validate(value);
    if (problem != null) throw ListingException(problem);
    await _commit(housing, {..._listings, value.type: value});
  }

  Future<void> setActive(ServiceType type, bool active) async {
    final current = _scope();
    await load();
    _check(current);
    final value = _listings[type];
    if (value != null) await save(value.withActive(active));
  }

  Future<void> archive(ServiceType type) async {
    final current = _scope();
    await load();
    _check(current);
    if (busy) throw const ListingException(ListingProblem.busy);
    if (api == null) {
      final item = _listings[type];
      if (item == null) return;
      final saved = {
        'housing': housing.name,
        '_revision': _revision,
        'listings': {
          ..._listings,
          type: item.withActive(false),
        }.values.map((v) => v.toJson()).toList(),
        'moderation': {
          ..._moderation,
          type.name: {'status': 'archived', 'reason': ''},
        },
      };
      if (!await _prefs!.setString(storageKey, jsonEncode(saved))) {
        throw const ListingException(ListingProblem.storage);
      }
      _check(current);
      _apply(saved);
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final saved = await api!.request(
        'POST',
        '/me/listings/${type.name}/archive',
        {'_revision': _revision},
      );
      _check(current);
      _apply(saved);
    } finally {
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> setHousing(HousingType value) async {
    final current = _scope();
    await load();
    _check(current);
    final updated = {..._listings};
    final boarding = updated[ServiceType.boarding];
    if (value == HousingType.apartment &&
        boarding != null &&
        (boarding.capacity ?? 1) > 1) {
      // A smaller home requires the sitter to review and reactivate their terms.
      updated[ServiceType.boarding] = ServiceListing(
        type: boarding.type,
        pets: boarding.pets,
        dailyPrice: boarding.dailyPrice,
        location: boarding.location,
        capacity: 1,
        active: false,
      );
    }
    await _commit(value, updated);
  }

  Future<void> _commit(
    HousingType housing,
    Map<ServiceType, ServiceListing> values,
  ) async {
    final current = _scope();
    _check(current);
    if (busy) throw const ListingException(ListingProblem.busy);
    busy = true;
    notifyListeners();
    try {
      final payload = {
        '_revision': _revision,
        'housing': housing.name,
        'listings': values.values.map((v) => v.toJson()).toList(),
      };
      if (api != null) {
        final saved = await api!.request('PUT', '/me/listings', payload);
        _check(current);
        await _prefs!.remove(storageKey);
        _check(current);
        _apply(saved);
      } else {
        final saved = await _prefs!.setString(storageKey, jsonEncode(payload));
        _check(current);
        if (!saved) throw const ListingException(ListingProblem.storage);
        _housing = housing;
        _listings = values;
      }
    } finally {
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }
}
