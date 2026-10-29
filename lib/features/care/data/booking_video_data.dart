typedef VideoData = Map<String, dynamic>;
const _slots = ['morning', 'evening'];
bool _text(Object? v, int max) => v is String && v.runes.length <= max;
bool _day(Object? v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse(v)?.toIso8601String().substring(0, 10) == v;
DateTime? _time(Object? v) =>
    v is String && v.length <= 64 && RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(v)
    ? DateTime.tryParse(v)?.toUtc()
    : null;
bool _integer(Object? v, int min, int max) => v is int && v >= min && v <= max;
Never _bad() => throw const FormatException('Invalid video overview');

/// Validate the whole page before publishing any policy, media or follow-up.
VideoData videoOverview(VideoData value, String bookingId, {String? day}) {
  if (value['bookingId'] != bookingId ||
      !_day(value['day']) ||
      ![
        'accepted',
        'active',
        'completed',
        'disputed',
        'cancelled',
      ].contains(value['status']) ||
      value['canUpload'] is! bool ||
      value['serviceAvailable'] is! bool ||
      value['retentionDays'] != 30 ||
      value['policy'] is! Map ||
      value['pets'] is! List ||
      value['items'] is! List ||
      value['followups'] is! List) {
    _bad();
  }
  final policy = value['policy'] as Map;
  final now = _time(policy['serverTime']);
  if (now == null ||
      policy['timezone'] != 'Asia/Tashkent' ||
      !_day(policy['today']) ||
      policy['today'] !=
          now
              .add(const Duration(hours: 5))
              .toIso8601String()
              .substring(0, 10) ||
      value['day'] != (day ?? policy['today']) ||
      (value['day'] as String).compareTo(policy['today']) > 0 ||
      policy['minSeconds'] != 10 ||
      policy['maxSeconds'] != 60 ||
      policy['maxBytes'] != 32 * 1024 * 1024 ||
      policy['slots'] is! List ||
      (policy['slots'] as List).length != 2) {
    _bad();
  }
  final seenSlots = <String>{};
  for (final s in policy['slots']) {
    if (s is! Map ||
        !_slots.contains(s['slot']) ||
        !seenSlots.add(s['slot']) ||
        s['open'] is! bool) {
      _bad();
    }
    final morning = s['slot'] == 'morning';
    final opens = DateTime.parse(
      '${policy['today']}T${morning ? '07' : '18'}:00:00+05:00',
    );
    final closes = DateTime.parse(
      '${policy['today']}T${morning ? '11' : '22'}:00:00+05:00',
    );
    if (_time(s['opensAt']) != opens ||
        _time(s['closesAt']) != closes ||
        s['open'] != (!now.isBefore(opens) && now.isBefore(closes))) {
      _bad();
    }
  }
  if (value['canUpload'] == true &&
      (value['status'] != 'active' ||
          value['serviceAvailable'] != true ||
          value['day'] != policy['today'])) {
    _bad();
  }
  final pets = value['pets'] as List, petIds = <String>{};
  if (pets.isEmpty || pets.length > 30) {
    _bad();
  }
  for (final pet in pets) {
    if (pet is! Map ||
        !_text(pet['id'], 100) ||
        pet['id'] == '' ||
        !petIds.add(pet['id']) ||
        !_text(pet['name'], 200) ||
        (pet['name'] as String).trim().isEmpty) {
      _bad();
    }
  }
  final ids = <String>{}, targets = <String>{};
  if ((value['items'] as List).length > pets.length * 2) {
    _bad();
  }
  for (final item in value['items']) {
    if (item is! Map ||
        item['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(item['id']) ||
        !ids.add(item['id']) ||
        !petIds.contains(item['petId']) ||
        item['day'] != value['day'] ||
        !_slots.contains(item['slot']) ||
        !targets.add('${item['petId']}:${item['slot']}') ||
        !_integer(item['durationMs'], 10000, 60000) ||
        !_integer(item['bytes'], 12, 32 * 1024 * 1024) ||
        !_integer(item['width'], 16, 1920) ||
        !_integer(item['height'], 16, 1920) ||
        item['width'] * item['height'] > 1920 * 1080 ||
        _time(item['created']) == null ||
        item['available'] is! bool ||
        (item['expiresAt'] != null && _time(item['expiresAt']) == null)) {
      _bad();
    }
    final expiry = _time(item['expiresAt']);
    if ((item['available'] == false && expiry == null) ||
        (item['available'] == true &&
            expiry != null &&
            !now.isBefore(expiry))) {
      _bad();
    }
  }
  final followups = value['followups'] as List, checks = <String>{};
  if (followups.length > 2) {
    _bad();
  }
  for (final row in followups) {
    if (row is! Map ||
        !_slots.contains(row['slot']) ||
        !checks.add(row['slot']) ||
        _time(row['dueAt']) == null ||
        row['canExplain'] is! bool ||
        row['missingPetIds'] is! List ||
        row['explanations'] is! List) {
      _bad();
    }
    final due = DateTime.parse(
      '${value['day']}T${row['slot'] == 'morning' ? '11' : '22'}:00:00+05:00',
    );
    if (_time(row['dueAt']) != due ||
        (row['canExplain'] == true && now.isBefore(due))) {
      _bad();
    }
    final missing = <String>{}, notes = <String>{};
    for (final pet in row['missingPetIds']) {
      if (pet is! String ||
          !petIds.contains(pet) ||
          !missing.add(pet) ||
          targets.contains('$pet:${row['slot']}')) {
        _bad();
      }
    }
    if ((row['explanations'] as List).length > pets.length) {
      _bad();
    }
    for (final note in row['explanations']) {
      if (note is! Map ||
          !petIds.contains(note['petId']) ||
          !notes.add(note['petId']) ||
          !_text(note['reason'], 1000) ||
          (note['reason'] as String).trim().isEmpty ||
          note['emergency'] is! bool ||
          _time(note['created']) == null) {
        _bad();
      }
    }
  }
  return value;
}
