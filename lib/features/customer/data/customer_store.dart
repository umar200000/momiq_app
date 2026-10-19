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
const customerSitters = <CJson>[
  {
    'id': 'hoji',
    'name': 'Hoji Sherhojiyiv',
    'photo': 0,
    'rating': 4.9,
    'reviews': 24,
    'years': 3,
    'distance': 2.0,
    'price': 80000,
    'pets': ['Mushuk'],
    'service': 0,
    'capacity': 3,
    'occupied': 0,
    'homePhotos': [0, 1, 2],
  },
  {
    'id': 'nilufar',
    'name': 'Nilufar Karimova',
    'photo': 1,
    'rating': 4.8,
    'reviews': 17,
    'years': 4,
    'distance': 3.0,
    'price': 70000,
    'pets': ['It', 'Mushuk', 'Boshqa'],
    'service': 1,
    'capacity': 3,
    'occupied': 0,
    'homePhotos': <int>[],
  },
  {
    'id': 'aziz',
    'name': 'Aziz Rahimov',
    'photo': 0,
    'rating': 4.7,
    'reviews': 31,
    'years': 2,
    'distance': 5.0,
    'price': 150000,
    'pets': ['It'],
    'service': 2,
    'capacity': 1,
    'occupied': 0,
    'homePhotos': [0, 1, 2],
  },
  {
    'id': 'sitora',
    'name': 'Sitora Karimova',
    'photo': 1,
    'rating': 4.9,
    'reviews': 12,
    'years': 5,
    'distance': 4.0,
    'price': 90000,
    'pets': ['It'],
    'service': 0,
    'capacity': 3,
    'occupied': 3,
    'busyDays': 3,
    'homePhotos': [0, 1, 2],
  },
  {
    'id': 'malika',
    'name': 'Malika Aliyeva',
    'photo': 1,
    'rating': 4.8,
    'reviews': 15,
    'years': 3,
    'distance': 6.0,
    'price': 75000,
    'pets': ['It', 'Mushuk', 'Boshqa'],
    'service': 1,
    'occupied': 1,
    'busyDays': 2,
    'homePhotos': <int>[],
  },
];
CJson customerSitter(String id) =>
    customerSitters.firstWhere((s) => s['id'] == id);
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
  final CustomerFeedRepository feedRepository;
  List<CJson> _sitters = customerSitters
      .map((s) => Map<String, dynamic>.from(s))
      .toList();
  List<CJson> get sitters => List.unmodifiable(_sitters);
  int _feedVersion = 0;
  bool _disposed = false;
  CustomerApi? api;
  Timer? _syncTimer;
  bool _syncing = false;
  String? syncError;
  bool get remote => api != null;
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
    ])
      key: data[key],
    'language': data['language'] ?? 'uz',
  };
  Future<void> refreshRemote() async {
    if (api == null || busy || _syncing || _disposed) return;
    _syncing = true;
    try {
      final account = await api!.request('GET', '/me');
      final messages = await api!.request('GET', '/messages');
      if (_disposed || busy) return;
      _data.addAll(Map<String, dynamic>.from(account['account']));
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
    final version = ++_feedVersion;
    final result = await feedRepository.fetchSitters(location: location);
    if (_disposed || version != _feedVersion) return;
    _sitters = result;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
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
    this.feedRepository = const MockCustomerFeedRepository(),
  }) : preferences = preferences ?? SharedPreferences.getInstance,
       petSession = petSession ?? CustomerPetSession.current {
    this.petSession.addListener(_petsChanged);
  }
  CJson get profile => Map<String, dynamic>.from(_data['profile'] as Map);
  List<CJson> list(String key) =>
      (key == 'pets' && api == null ? petSession.pets : _data[key] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  List<String> get favorites => List<String>.from(_data['favorites'] as List);
  CJson get notifications =>
      Map<String, dynamic>.from(_data['notifications'] as Map);
  Future<void> load() async {
    if (loaded) return;
    api ??= await CustomerApi.restore();
    final raw = (await preferences()).getString(_cacheKey);
    _data = raw == null
        ? _seed()
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    _data['pets'] =
        <CJson>[]; // Never restore pets from an earlier app session.
    if (api != null) {
      final account = await api!.request('GET', '/me');
      final messages = await api!.request('GET', '/messages');
      _data.addAll(Map<String, dynamic>.from(account['account']));
      _data['messages'] = messages['messages'];
      if (AppLanguage.current.value != _data['language']) {
        await AppLanguage.select(_data['language'] ?? 'uz');
      }
      if (!_disposed) {
        _syncTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => refreshRemote(),
        );
      }
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> update(void Function(CJson next) change) async {
    if (busy) throw StateError('Saqlanmoqda. Biroz kuting.');
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
  Future<void> saveItem(String key, CJson value) async {
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
    });
  }

  /// Mock occupancy is constant; local requests reserve their selected dates.
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
      var occupied = day.isBefore(mockSitterFreeDate(sitter))
          ? (sitter['occupied'] as int? ?? 0)
          : 0;
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

  DateTime firstAvailableDate(CJson sitter, {DateTime? after}) {
    final start = calendarDate(after ?? DateTime.now());
    final candidates = <DateTime>{start, mockSitterFreeDate(sitter)};
    for (final b in list('bookings')) {
      if (b['sitter'] == sitter['id'] &&
          b['sample'] != true &&
          ['pending', 'active'].contains(b['status'])) {
        final end = DateTime.parse(b['to']);
        candidates.add(DateTime(end.year, end.month, end.day + 1));
      }
    }
    final sorted = candidates.where((d) => !d.isBefore(start)).toList()..sort();
    return sorted.firstWhere((d) => availablePlaces(sitter, from: d) > 0);
  }

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
    final sitter = customerSitter(sitterId);
    final ids = (petIds ?? [?petId]).toSet();
    if (ids.isEmpty) throw ArgumentError('Hayvonni tanlang.');
    final pets = ids
        .map((id) => list('pets').firstWhere((p) => p['id'] == id))
        .toList();
    if (pets.any((p) => !allowedCustomerPetTypes(sitter).contains(p['type']))) {
      throw ArgumentError('Hayvon ushbu xizmatga mos emas.');
    }
    if (calendarDate(from).isBefore(calendarDate(DateTime.now())) ||
        careDays(from, to) < 1) {
      throw ArgumentError('Sanalarni tekshiring.');
    }
    if (sitter['service'] == 1 &&
        (address['lat'] is! num ||
            address['lon'] is! num ||
            (address['lat'] as num).abs() > 90 ||
            (address['lon'] as num).abs() > 180 ||
            !(address['lat'] as num).isFinite ||
            !(address['lon'] as num).isFinite ||
            '${address['address'] ?? ''}'.trim().isEmpty)) {
      throw ArgumentError('Uy manzilini xaritadan belgilang.');
    }
    if (pets.length > availablePlaces(sitter, from: from, to: to)) {
      throw StateError('Tanlangan hayvonlar uchun bo‘sh joy yetarli emas.');
    }
    final care = <String, CJson>{};
    for (final pet in pets) {
      final ins = petInstructions == null
          ? instructions
          : petInstructions[pet['id']];
      care[pet['id']] = ins ?? {};
    }
    final id = 'MQ-${DateTime.now().microsecondsSinceEpoch}';
    await update(
      (d) => (d['bookings'] as List).insert(0, {
        'id': id,
        'sitter': sitterId,
        'pet': pets.first,
        'pets': pets,
        'petInstructions': care,
        'petPassports': {
          for (final id in ids)
            if (petPassports.containsKey(id)) id: petPassports[id],
        },
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'status': 'pending',
        'price': sitter['price'],
        'service': sitter['service'],
        'instructions': care[pets.first['id']],
        'address': address,
        'review': null,
      }),
    );
    return id;
  }

  Future<void> cancel(String id, String reason) => update((d) {
    final b = (d['bookings'] as List).firstWhere((b) => b['id'] == id);
    if (!['pending', 'active'].contains(b['status'])) {
      throw StateError('Buyurtma yakunlangan.');
    }
    if (reason.trim().isEmpty) throw ArgumentError('Sababni kiriting.');
    b['status'] = 'cancelled';
    b['cancelReason'] = reason.trim();
  });
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

  CJson _seed() {
    final today = calendarDate(DateTime.now());
    final pets = <CJson>[
      {
        'id': 'momi',
        'name': 'Momi',
        'type': 'Mushuk',
        'age': '2',
        'sex': 'Urg‘ochi',
        'breed': '',
        'notes': 'Kuniga 3 mahal ovqat',
        'photo': null,
      },
      {
        'id': 'boni',
        'name': 'Boni',
        'type': 'It',
        'age': '3',
        'sex': 'Erkak',
        'breed': '',
        'notes': 'Faol va do‘stona',
        'photo': null,
      },
    ];
    CJson booking(String id, int ago, String status) => {
      'id': id,
      'sitter': 'hoji',
      'pet': pets.first,
      'from': today.subtract(Duration(days: ago)).toIso8601String(),
      'to': today.subtract(Duration(days: ago - 2)).toIso8601String(),
      'status': status,
      'price': 80000,
      'service': 0,
      'instructions': {
        'meals': ['08:00', '13:00', '19:00'],
        'food': 'Mijoz ko‘rsatmasi bo‘yicha',
        'medicine': true,
        'medicineTime': '09:00',
        'medicineNote': 'Mijoz bilan kelishilgan ko‘rsatma',
        'walk': true,
        'walkTime': '18:00',
        'walkMinutes': '20',
      },
      'address': {
        'latitude': 41.2995,
        'longitude': 69.2726,
        'address': 'Toshkent, Oybek ko‘chasi, 12',
      },
      'review': null,
      'sample': true,
    };
    return {
      'profile': {'first': 'Madina', 'last': 'Karimova', 'photo': null},
      'pets': <CJson>[],
      'favorites': <String>[],
      'addresses': <CJson>[],
      'bookings': [
        booking('MQ-DEMO-01', 0, 'active'),
        booking('MQ-DEMO-02', 7, 'completed'),
      ],
      'notifications': {'orders': true, 'chat': true, 'video': true},
      'messages': [
        {
          'id': 'welcome',
          'sitter': 'hoji',
          'mine': false,
          'text': 'Salom! Momi o‘zini yaxshi his qilyapti.',
          'time': DateTime.now().toIso8601String(),
        },
      ],
      'support': <CJson>[],
    };
  }
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

final _mockAvailabilityStart = calendarDate(DateTime.now());
DateTime mockSitterFreeDate(CJson sitter) => DateTime(
  _mockAvailabilityStart.year,
  _mockAvailabilityStart.month,
  _mockAvailabilityStart.day + (sitter['busyDays'] as int? ?? 0),
);
