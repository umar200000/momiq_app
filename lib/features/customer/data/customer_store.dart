import '../../../core/localization/app_language.dart';
import 'dart:async';
import 'customer_api.dart';
import 'customer_feed_repository.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CJson = Map<String, dynamic>;
const customerServices = [
  'Enaga uyida qarash',
  'Uyimga kelib qarash',
  'Shaxsiy enaga',
];
final customerSitters = <CJson>[];
CJson customerSitter(String id) => customerSitters.firstWhere(
  (s) => s['id'] == id,
  orElse: () => {'id': id, 'name': 'Enaga mavjud emas', 'unavailable': true},
);
DateTime calendarDate(DateTime v) => DateTime(v.year, v.month, v.day);
int careDays(DateTime from, DateTime to) =>
    DateTime.utc(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
    1;
String shortDate(String value) {
  final d = DateTime.parse(value);
  return '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

List<String> allowedCustomerPetTypes(CJson sitter) => sitter['service'] == 1
    ? ['It', 'Mushuk', 'Boshqa']
    : (sitter['pets'] as List)
          .where((type) => type == 'It' || type == 'Mushuk')
          .cast<String>()
          .toSet()
          .toList();
String customerPetType(CJson pet) =>
    pet['type'] == 'Boshqa' && '${pet['otherType'] ?? ''}'.trim().isNotEmpty
    ? pet['otherType']
    : pet['type'];
String customerPetName(CJson pet) =>
    '${pet['name'] ?? ''}'.trim().isEmpty ? customerPetType(pet) : pet['name'];
String customerPetDescription(CJson pet) =>
    '${customerPetType(pet)}${'${pet['age'] ?? ''}'.isEmpty ? '' : ' · ${pet['age']} yosh'}';

/// Process-memory only: shared across routes/stores, empty on a fresh app launch.
class CustomerPetSession extends ChangeNotifier {
  static final current = CustomerPetSession();
  final List<CJson> _pets = [];
  List<CJson> get pets =>
      _pets.map((p) => Map<String, dynamic>.from(p)).toList();
  void clear() {
    _pets.clear();
    notifyListeners();
  }

  void save(CJson pet) {
    if (!['It', 'Mushuk', 'Boshqa'].contains(pet['type']) ||
        '${pet['photo'] ?? ''}'.isEmpty ||
        (pet['type'] == 'Boshqa' &&
            '${pet['otherType'] ?? ''}'.trim().isEmpty)) {
      throw ArgumentError('Rasm va hayvon turini kiriting.');
    }
    final i = _pets.indexWhere((p) => p['id'] == pet['id']);
    final copy = Map<String, dynamic>.from(pet);
    if (i < 0) {
      _pets.add(copy);
    } else {
      _pets[i] = copy;
    }
    notifyListeners();
  }
}

class CustomerStore extends ChangeNotifier {
  static const storageKey = 'momiq.customer.v1';
  CJson _data = {};
  final int _sessionVersion = CustomerApi.sessionVersion;
  final CustomerFeedRepository feedRepository;
  List<CJson> _sitters = customerSitters
      .map((s) => Map<String, dynamic>.from(s))
      .toList();
  List<CJson> get sitters => List.unmodifiable(_sitters);
  int _feedVersion = 0;
  bool feedLoading = false;
  String? feedError;
  CustomerCoordinates? feedLocation;
  bool _disposed = false;
  CustomerApi? api;
  bool _syncing = false;
  String? syncError;
  bool get remote => api != null;
  int? get revision => _data['_revision'] as int?;
  String get _cacheKey =>
      api == null ? storageKey : '$storageKey.${api!.userId}';
  Map<String, dynamic> _account(Map<String, dynamic> data) => {
    for (final key in [
      'profile',
      'favorites',
      'addresses',
      'notifications',
      'pets',
      'support',
      'sitterProfile',
    ])
      key: data[key],
    'language': data['language'] ?? 'uz',
    if (data.containsKey('_revision')) '_revision': data['_revision'],
  };
  Future<void> refreshRemote() async {
    if (api == null || busy || _syncing || _disposed) return;
    _syncing = true;
    try {
      final account = await api!.request('GET', '/me');
      final messages = await api!.request('GET', '/messages');
      if (_disposed || busy) return;
      if (_disposed || _sessionVersion != CustomerApi.sessionVersion) return;
      _data.addAll(Map<String, dynamic>.from(account['account']));
      await CustomerApi.rememberAccount(
        Map<String, dynamic>.from(account['account']),
      );
      _data['messages'] = messages['messages'];
      if (AppLanguage.current.value != _data['language']) {
        await AppLanguage.select(_data['language'] ?? 'uz');
      }
      syncError = null;
    } catch (e) {
      if (!_disposed) syncError = e.toString();
    } finally {
      _syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshSitters({CustomerCoordinates? location}) async {
    if (_disposed || _sessionVersion != CustomerApi.sessionVersion) return;
    final version = ++_feedVersion;
    feedLoading = true;
    feedError = null;
    feedLocation = location;
    notifyListeners();
    try {
      final result = await feedRepository.fetchSitters(location: location);
      if (_disposed ||
          version != _feedVersion ||
          _sessionVersion != CustomerApi.sessionVersion) {
        return;
      }
      _sitters = result;
      customerSitters
        ..clear()
        ..addAll(result);
    } catch (_) {
      if (!_disposed &&
          version == _feedVersion &&
          _sessionVersion == CustomerApi.sessionVersion) {
        feedError = 'catalog_unavailable';
      }
      rethrow;
    } finally {
      if (!_disposed &&
          version == _feedVersion &&
          _sessionVersion == CustomerApi.sessionVersion) {
        feedLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    petSession.removeListener(_petsChanged);
    _disposed = true;
    super.dispose();
  }

  bool loaded = false, busy = false;
  final Future<SharedPreferences> Function() preferences;
  final CustomerPetSession petSession;
  void _petsChanged() {
    if (!_disposed) notifyListeners();
  }

  CustomerStore({
    Future<SharedPreferences> Function()? preferences,
    CustomerPetSession? petSession,
    this.feedRepository = const ApiCustomerFeedRepository(),
  }) : preferences = preferences ?? SharedPreferences.getInstance,
       petSession = petSession ?? CustomerPetSession.current {
    this.petSession.addListener(_petsChanged);
  }
  CJson get profile => Map<String, dynamic>.from(_data['profile'] as Map);
  List<CJson> get allPets =>
      (api == null ? petSession.pets : _data['pets'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  List<CJson> get archivedPets =>
      allPets.where((p) => p['archived'] == true).toList();
  List<CJson> list(String key) =>
      (key == 'pets' && api == null ? petSession.pets : _data[key] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((v) => key != 'pets' || v['archived'] != true)
          .toList();

  Future<void> archivePet(
    String id,
    bool archived, {
    int? expectedRevision,
  }) async {
    if (_disposed || _sessionVersion != CustomerApi.sessionVersion) {
      throw StateError('Sessiya tugagan');
    }
    if (busy) throw StateError('Saqlanmoqda. Biroz kuting.');
    final pet = allPets.where((p) => p['id'] == id).firstOrNull;
    if (pet == null) throw StateError('Hayvon topilmadi');
    if (api == null) {
      petSession.save({...pet, 'archived': archived});
      return;
    }
    if (expectedRevision != revision) {
      throw CustomerApiException('Profil o‘zgargan. Qayta yuklang.', 409);
    }
    busy = true;
    notifyListeners();
    try {
      final result = await api!.request('POST', '/me/pets/archive', {
        'petId': id,
        'archived': archived,
        '_revision': expectedRevision,
      });
      if (_disposed || _sessionVersion != CustomerApi.sessionVersion) {
        throw StateError('Sessiya tugagan');
      }
      _data.addAll(Map<String, dynamic>.from(result['account']));
      await CustomerApi.rememberAccount(_account(_data));
      // Server remains authoritative if local cache is unavailable.
      await (await preferences()).setString(_cacheKey, jsonEncode(_data));
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  List<String> get favorites => List<String>.from(_data['favorites'] as List);
  CJson get notifications =>
      Map<String, dynamic>.from(_data['notifications'] as Map);
  Future<void> load() async {
    if (loaded) return;
    api ??= await CustomerApi.restore();
    final raw = (await preferences()).getString(_cacheKey);
    _data = raw == null
        ? _emptyAccount()
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final legacyDemo = (_data['bookings'] as List? ?? []).any(
      (b) => b['sample'] == true,
    );
    _data['bookings'] = <CJson>[];
    if (api == null) {
      _data['messages'] = <CJson>[];
      _data['favorites'] = <String>[];
      if (legacyDemo &&
          _data['profile']['first'] == 'Madina' &&
          _data['profile']['last'] == 'Karimova') {
        _data['profile'] = {'first': '', 'last': '', 'photo': null};
      }
    }
    _data['pets'] =
        <CJson>[]; // Never restore pets from an earlier app session.
    if (api != null) {
      final account = await api!.request('GET', '/me');
      final messages = await api!.request('GET', '/messages');
      if (_disposed || _sessionVersion != CustomerApi.sessionVersion) return;
      _data.addAll(Map<String, dynamic>.from(account['account']));
      await CustomerApi.rememberAccount(
        Map<String, dynamic>.from(account['account']),
      );
      _data['messages'] = messages['messages'];
      if (AppLanguage.current.value != _data['language']) {
        await AppLanguage.select(_data['language'] ?? 'uz');
      }
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> update(
    void Function(CJson next) change, {
    int? expectedRevision,
  }) async {
    if (_disposed || _sessionVersion != CustomerApi.sessionVersion) {
      throw StateError('Sessiya tugagan');
    }
    if (busy) throw StateError('Saqlanmoqda. Biroz kuting.');
    if (api != null &&
        expectedRevision != null &&
        expectedRevision != revision) {
      throw CustomerApiException(
        'Profil boshqa qurilmada o‘zgargan. Sahifani qayta ochib, o‘zgarishni takrorlang.',
        409,
      );
    }
    busy = true;
    if (!_disposed) notifyListeners();
    try {
      final next = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_data)) as Map,
      );
      change(next);
      if (api == null) next['pets'] = <CJson>[];
      if (api != null &&
          jsonEncode(_account(next)) != jsonEncode(_account(_data))) {
        final saved = await api!.request('PUT', '/me', _account(next));
        next.addAll(Map<String, dynamic>.from(saved['account']));
      }
      if (_disposed || _sessionVersion != CustomerApi.sessionVersion) {
        throw StateError('Sessiya tugagan');
      }
      if (api != null) await CustomerApi.rememberAccount(_account(next));
      if (!await (await preferences()).setString(_cacheKey, jsonEncode(next))) {
        throw StateError('Saqlanmadi');
      }
      _data = next;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> favorite(String id) => update((d) {
    final items = d['favorites'] as List;
    items.contains(id) ? items.remove(id) : items.add(id);
  });
  Future<void> saveItem(
    String key,
    CJson value, {
    int? expectedRevision,
  }) async {
    if (['messages', 'support'].contains(key) && api == null) {
      throw StateError('Xabar yuborish uchun hisobingizga kiring.');
    }
    if (key == 'messages' && api != null) {
      final result = await api!.request('POST', '/messages', {
        'sitter': value['sitter'],
        'text': value['text'] ?? '',
        'image': value['image'],
        'requestId': value['id'],
      });
      _data['messages'] = result['messages'];
      if (!_disposed) notifyListeners();
      return;
    }
    if (key == 'pets' && api == null) {
      petSession.save(value);
      return;
    }
    await update((d) {
      final items = d[key] as List;
      final i = items.indexWhere((v) => v['id'] == value['id']);
      if (i < 0) {
        items.add(value);
      } else {
        items[i] = value;
      }
    }, expectedRevision: expectedRevision);
  }

  /// Availability is based on supplied data only.
  int availablePlaces(CJson sitter, {DateTime? from, DateTime? to}) {
    final capacity = sitterCapacity(sitter);
    final start = calendarDate(from ?? DateTime.now());
    final end = calendarDate(to ?? from ?? DateTime.now());
    final orders = list('bookings').where(
      (b) =>
          b['sitter'] == sitter['id'] &&
          b['sample'] != true &&
          ['pending', 'active'].contains(b['status']),
    );
    var peak = 0;
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      var occupied = sitter['occupied'] as int? ?? 0;
      for (final b in orders) {
        if (!day.isBefore(calendarDate(DateTime.parse(b['from']))) &&
            !day.isAfter(calendarDate(DateTime.parse(b['to'])))) {
          occupied += bookingPets(b).length;
        }
      }
      if (occupied > peak) peak = occupied;
    }
    if (sitter['service'] == 1) return peak > 0 ? 0 : 3;
    return (capacity - peak).clamp(0, capacity);
  }

  // Earliest selectable date; does not promise availability.
  DateTime firstAvailableDate(CJson sitter, {DateTime? after}) =>
      calendarDate(after ?? DateTime.now());

  Future<String> book({
    required String sitterId,
    String? petId,
    List<String>? petIds,
    Map<String, CJson>? petInstructions,
    required DateTime from,
    required DateTime to,
    CJson instructions = const {},
    Map<String, String> petPassports = const {},
    required CJson address,
  }) async {
    throw StateError('Buyurtma berish xizmati hali ulanmagan.');
  }

  Future<void> cancel(String id, String reason) async {
    throw StateError('Buyurtmalar xizmati hali ulanmagan.');
  }

  Future<void> send(String sitter, String text) async {
    if (text.trim().isEmpty) return;
    await saveItem('messages', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'sitter': sitter,
      'mine': true,
      'text': text.trim(),
      'time': DateTime.now().toIso8601String(),
    });
  }

  CJson _emptyAccount() => {
    'profile': {'first': '', 'last': '', 'photo': null},
    'pets': <CJson>[],
    'favorites': <String>[],
    'addresses': <CJson>[],
    'bookings': <CJson>[],
    'messages': <CJson>[],
    'support': <CJson>[],
    'notifications': {'orders': true, 'chat': true, 'video': true},
    'language': 'uz',
  };
}

// Older single-pet orders remain readable.
List<CJson> bookingPets(CJson booking) =>
    (booking['pets'] as List? ?? [booking['pet']])
        .map((p) => CJson.from(p))
        .toList();
String bookingPetNames(CJson booking) =>
    bookingPets(booking).map(customerPetName).join(', ');
CJson bookingPetCare(CJson booking, CJson pet) => CJson.from(
  booking['petInstructions']?[pet['id']] ?? booking['instructions'],
);
int bookingTotal(CJson booking) =>
    (booking['price'] as num).toInt() *
    bookingPets(booking).length *
    careDays(DateTime.parse(booking['from']), DateTime.parse(booking['to']));

int sitterCapacity(CJson sitter) => sitter['service'] == 2
    ? 1
    : sitter['service'] == 1
    ? 3
    : (sitter['capacity'] as int? ?? 1).clamp(1, 3);
