import 'dart:convert';
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
      address.trim().isNotEmpty;
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

/// Device-local listings. Commit to storage before notifying the UI.
class ListingStore extends ChangeNotifier {
  ListingStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;
  static final instance = ListingStore();
  void resetSession() {
    _listings = {};
    _housing = HousingType.apartment;
    _loaded = false;
    _loading = null;
    _prefs = null;
    notifyListeners();
  }

  static const storageKey = 'momiq.services.v1';
  final Future<SharedPreferences> Function() _preferences;
  Future<void>? _loading;
  bool _loaded = false;
  SharedPreferences? _prefs;
  HousingType _housing = HousingType.apartment;
  Map<ServiceType, ServiceListing> _listings = {};
  bool busy = false;
  HousingType get housing => _housing;
  int get maxCapacity => housing == HousingType.apartment ? 1 : 3;
  ServiceListing? operator [](ServiceType type) => _listings[type];

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _read()
        .then((_) {
          _loaded = true;
          _loading = null;
        })
        .catchError((Object error) {
          _loading = null;
          throw error;
        });
  }

  Future<void> _read() async {
    _prefs = await _preferences();
    final raw = _prefs!.getString(storageKey);
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
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
    notifyListeners();
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
    if (value.type != ServiceType.homeVisit &&
        value.location?.isValid != true) {
      return ListingProblem.location;
    }
    return null;
  }

  Future<void> save(ServiceListing value) async {
    await load();
    final problem = validate(value);
    if (problem != null) throw ListingException(problem);
    await _commit(housing, {..._listings, value.type: value});
  }

  Future<void> setActive(ServiceType type, bool active) async {
    await load();
    final value = _listings[type];
    if (value != null) await save(value.withActive(active));
  }

  Future<void> setHousing(HousingType value) async {
    await load();
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
    if (busy) throw const ListingException(ListingProblem.busy);
    busy = true;
    notifyListeners();
    try {
      final saved = await _prefs!.setString(
        storageKey,
        jsonEncode({
          'housing': housing.name,
          'listings': values.values.map((v) => v.toJson()).toList(),
        }),
      );
      if (!saved) throw const ListingException(ListingProblem.storage);
      _housing = housing;
      _listings = values;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
