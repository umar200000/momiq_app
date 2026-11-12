import 'package:flutter/foundation.dart' show mapEquals;

typedef CareData = Map<String, dynamic>;
const _categories = ['food', 'water', 'walk', 'medicine', 'other'];
bool _text(Object? v, int limit) => v is String && v.runes.length <= limit;
bool _number(Object? v) =>
    v is String && RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(v);
bool _day(Object? v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse(v)?.toIso8601String().substring(0, 10) == v;
bool _time(Object? v) =>
    v is String && v.length <= 64 && DateTime.tryParse(v) != null;
Never _bad() => throw const FormatException('Invalid care response');

CareData careEntry(Object? value) {
  if (value is! Map ||
      !_number(value['id']) ||
      !_text(value['petId'], 100) ||
      value['petId'] == '' ||
      value['revision'] is! int ||
      value['revision'] < 1 ||
      !_time(value['created']) ||
      value['payload'] is! Map) {
    _bad();
  }
  final p = value['payload'] as Map;
  if (value['kind'] == 'instructions') {
    if (value['actorRole'] != 'customer' ||
        value['day'] != '' ||
        value['category'] != '' ||
        p.length != 6 ||
        !_categories.every((key) => _text(p[key], 2000)) ||
        !_text(p['reason'], 500) ||
        (p['reason'] as String).trim().isEmpty) {
      _bad();
    }
  } else if (value['kind'] == 'report') {
    if (value['actorRole'] != 'sitter' ||
        !_day(value['day']) ||
        !_categories.contains(value['category']) ||
        p.length != 2 ||
        !['done', 'skipped', 'undone'].contains(p['state']) ||
        !_text(p['note'], 2000) ||
        (p['state'] != 'done' && (p['note'] as String).trim().isEmpty)) {
      _bad();
    }
  } else {
    _bad();
  }
  return {...CareData.from(value), 'payload': CareData.from(p)};
}

CareData careOverview(CareData value, String bookingId, {String? day}) {
  if (value['bookingId'] != bookingId ||
      value['timezone'] != 'Asia/Tashkent' ||
      ![
        'accepted',
        'active',
        'completed',
        'disputed',
        'cancelled',
      ].contains(value['status']) ||
      !['customer', 'sitter'].contains(value['myRole']) ||
      !_day(value['today']) ||
      !_day(value['day']) ||
      (value['day'] as String).compareTo(value['today']) > 0 ||
      (day != null && value['day'] != day) ||
      !_text(value['originalInstructions'], 4000) ||
      value['canEditInstructions'] is! bool ||
      value['canReport'] is! bool ||
      value['pets'] is! List ||
      (value['pets'] as List).isEmpty ||
      (value['pets'] as List).length > 30) {
    _bad();
  }
  if (value['canReport'] == true &&
      (value['myRole'] != 'sitter' ||
          value['status'] != 'active' ||
          value['day'] != value['today'])) {
    _bad();
  }
  if (value['canEditInstructions'] == true &&
      (value['myRole'] != 'customer' ||
          !['active', 'accepted'].contains(value['status']))) {
    _bad();
  }
  final pets = <CareData>[], ids = <String>{};
  for (final pet in value['pets']) {
    if (pet is! Map ||
        !_text(pet['id'], 100) ||
        pet['id'] == '' ||
        !ids.add(pet['id']) ||
        !_text(pet['name'], 2000) ||
        !_text(pet['originalNotes'], 2000) ||
        !_text(pet['originalMedication'], 2000) ||
        pet['reports'] is! List ||
        pet['reports'].length > 5) {
      _bad();
    }
    final instruction = pet['instructions'] == null
        ? null
        : careEntry(pet['instructions']);
    if (instruction != null &&
        (instruction['petId'] != pet['id'] ||
            instruction['kind'] != 'instructions')) {
      _bad();
    }
    final reports = <CareData>[], categories = <String>{};
    for (final raw in pet['reports']) {
      final item = careEntry(raw);
      if (item['petId'] != pet['id'] ||
          item['kind'] != 'report' ||
          item['day'] != value['day'] ||
          !categories.add(item['category'])) {
        _bad();
      }
      reports.add(item);
    }
    pets.add({
      ...CareData.from(pet),
      'instructions': instruction,
      'reports': reports,
    });
  }
  return {...value, 'pets': pets};
}

CareData careHistory(CareData value, {String? before}) {
  final rows = value['items'], cursor = value['nextCursor'];
  if (rows is! List ||
      rows.length > 30 ||
      (cursor != null && !_number(cursor))) {
    _bad();
  }
  final items = <CareData>[];
  int? previous = before == null ? null : int.parse(before);
  for (final raw in rows) {
    final item = careEntry(raw), number = int.parse(item['id']);
    if (previous != null && number >= previous) _bad();
    previous = number;
    items.add(item);
  }
  if (cursor != null && (items.length != 30 || cursor != items.last['id'])) {
    _bad();
  }
  return {'items': items, 'nextCursor': cursor};
}

CareData? careDraft(CareData? value) {
  if (value == null) return null;
  if (value.length != 7 ||
      !value.keys.toSet().containsAll([
        'petId',
        'kind',
        'day',
        'category',
        'revision',
        'requestId',
        'payload',
      ]) ||
      value['requestId'] is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(value['requestId']) ||
      value['revision'] is! int ||
      value['revision'] < 0) {
    _bad();
  }
  careEntry({
    ...value,
    'id': '1',
    'revision': value['revision'] + 1,
    'actorRole': value['kind'] == 'instructions' ? 'customer' : 'sitter',
    'created': '2000-01-01T00:00:00Z',
  });
  return {...value, 'payload': CareData.from(value['payload'])};
}

CareData careAcknowledgement(
  CareData value,
  String bookingId,
  CareData request,
) {
  final item = careEntry(value);
  if (value['bookingId'] != bookingId ||
      value['requestId'] != request['requestId'] ||
      [
        'petId',
        'kind',
        'day',
        'category',
      ].any((key) => item[key] != request[key]) ||
      item['revision'] != request['revision'] + 1 ||
      !mapEquals(item['payload'], {
        for (final e in (request['payload'] as Map).entries)
          e.key: (e.value as String).trim(),
      })) {
    _bad();
  }
  return item;
}
