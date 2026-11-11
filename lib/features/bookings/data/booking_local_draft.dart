import 'dart:convert';

typedef LocalBookingData = Map<String, dynamic>;
Never _bad() => throw const FormatException('Invalid saved booking draft');
bool _keys(Map value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);
bool _text(Object? value, int max) =>
    value is String && value.runes.length <= max;
bool _id(Object? value) => _text(value, 120) && (value as String).isNotEmpty;
bool _request(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(value);
bool _quoteId(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

/// Incomplete forms are valid; malformed values must never enter text/picker UI.
LocalBookingData bookingForm(Object? value) {
  const keys = {
    'petIds',
    'startsAt',
    'endsAt',
    'addressId',
    'instructions',
    'petPassports',
  };
  if (value is! Map || !value.keys.every(keys.contains)) _bad();
  final ids = value['petIds'];
  if (ids != null &&
      (ids is! List ||
          ids.length > 30 ||
          !ids.every(_id) ||
          ids.toSet().length != ids.length)) {
    _bad();
  }
  for (final key in ['startsAt', 'endsAt']) {
    if (!value.containsKey(key)) continue;
    final time = value[key];
    if (time is! String ||
        time.length > 40 ||
        !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(time)) {
      _bad();
    }
    final parsed = DateTime.tryParse(time);
    // Match the server's datetime year range before UI timezone arithmetic.
    if (parsed == null || parsed.year < 1 || parsed.year > 9999) _bad();
  }
  if ((value.containsKey('addressId') && !_id(value['addressId'])) ||
      (value.containsKey('instructions') &&
          !_text(value['instructions'], 4000))) {
    _bad();
  }
  final passports = value['petPassports'];
  if (passports != null) {
    if (passports is! Map || passports.length > 30) _bad();
    for (final entry in passports.entries) {
      final encoded = entry.value;
      if (!_id(entry.key) ||
          encoded is! String ||
          encoded.isEmpty ||
          encoded.length > 4 * 1024 * 1024) {
        _bad();
      }
      try {
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) _bad();
      } on FormatException {
        _bad();
      }
    }
  }
  return Map<String, dynamic>.from(value);
}

LocalBookingData? bookingComposeDraft(LocalBookingData? value) {
  if (value == null) return null;
  if (!_keys(value, {'draft', 'quote', 'pending'})) _bad();
  final form = bookingForm(value['draft']);
  final quote = value['quote'], pending = value['pending'];
  if (quote != null && quote is! Map<String, dynamic>) _bad();
  if (pending != null &&
      (pending is! Map<String, dynamic> ||
          !_keys(pending, {'quoteId', 'requestId'}) ||
          !_quoteId(pending['quoteId']) ||
          !_request(pending['requestId']))) {
    _bad();
  }
  return {'draft': form, 'quote': quote, 'pending': pending};
}

LocalBookingData? bookingActionDraft(LocalBookingData? value) {
  if (value == null) return null;
  final body = value['body'];
  if (!_keys(value, {'action', 'body'}) ||
      ![
        'accept',
        'reject',
        'cancel',
        'start',
        'complete',
      ].contains(value['action']) ||
      body is! Map<String, dynamic> ||
      !_keys(body, {'revision', 'requestId', 'reason'}) ||
      body['revision'] is! int ||
      body['revision'] < 0 ||
      !_request(body['requestId']) ||
      !_text(body['reason'], 1000) ||
      (['reject', 'cancel'].contains(value['action']) &&
          (body['reason'] as String).trim().isEmpty)) {
    _bad();
  }
  return {'action': value['action'], 'body': Map<String, dynamic>.from(body)};
}
