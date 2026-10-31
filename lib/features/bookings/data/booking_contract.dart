typedef BookingData = Map<String, dynamic>;

const bookingStates = {
  'pending',
  'accepted',
  'active',
  'disputed',
  'completed',
  'cancelled',
  'rejected',
  'expired',
};
const _services = {'boarding', 'homeVisit', 'personal'};
final _bookingId = RegExp(r'^[a-f0-9]{32}$');
Never _invalid() => throw const FormatException('Buyurtma javobi mos kelmadi');
bool _id(Object? value) => value is String && _bookingId.hasMatch(value);
bool _positiveMoney(Object? value) =>
    value is int && value > 0 && value <= 100000000000;

DateTime _instant(Object? value) {
  if (value is! String ||
      value.length > 40 ||
      !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
    _invalid();
  }
  return DateTime.tryParse(value)?.toUtc() ?? _invalid();
}

void checkBookingQuote(BookingData quote, String listingId, BookingData draft) {
  final snapshot = quote['snapshot'];
  if (!_id(quote['id']) ||
      snapshot is! Map ||
      snapshot['listingId'] != listingId ||
      (listingId.endsWith(':homeVisit') &&
          (draft['addressId'] is! String ||
              (draft['addressId'] as String).isEmpty ||
              snapshot['addressId'] != draft['addressId'])) ||
      snapshot['datePolicy'] != 'elapsed-24h-v1' ||
      snapshot['customerPaysSitterDirectly'] != true ||
      (draft['instructions'] != null && draft['instructions'] is! String) ||
      snapshot['instructions'] != (draft['instructions'] ?? '').trim()) {
    _invalid();
  }
  final start = _instant(snapshot['startsAt']),
      end = _instant(snapshot['endsAt']);
  final created = _instant(quote['created']),
      expires = _instant(quote['expiresAt']);
  if (start != _instant(draft['startsAt']) ||
      end != _instant(draft['endsAt']) ||
      !end.isAfter(start) ||
      !expires.isAfter(created) ||
      expires.isAfter(start) ||
      expires.difference(created) > const Duration(minutes: 10)) {
    _invalid();
  }
  _checkAgreement(snapshot);
  final selected = draft['petIds'];
  final pets = snapshot['pets'] as List;
  if (selected is! List ||
      selected.length != pets.length ||
      pets.any((pet) => !selected.contains(pet['id']))) {
    _invalid();
  }
}

void _checkAgreement(Map snapshot) {
  final start = _instant(snapshot['startsAt']),
      end = _instant(snapshot['endsAt']);
  if (!end.isAfter(start) ||
      snapshot['listingId'] is! String ||
      snapshot['instructions'] is! String ||
      snapshot['sitterName'] is! String ||
      snapshot['customerName'] is! String ||
      snapshot['address'] is! Map ||
      snapshot['address']['address'] is! String) {
    _invalid();
  }
  final pets = snapshot['pets'], price = snapshot['price'];
  if (pets is! List ||
      pets.isEmpty ||
      pets.length > 30 ||
      price is! Map ||
      !_services.contains(price['service']) ||
      (snapshot['listingId'] as String).split(':').last != price['service'] ||
      price['rates'] is! List ||
      (price['rates'] as List).length != pets.length ||
      (price['service'] == 'personal' && pets.length != 1)) {
    _invalid();
  }
  final petIds = <String>{};
  for (final pet in pets) {
    if (pet is! Map ||
        pet['id'] is! String ||
        (pet['id'] as String).isEmpty ||
        !petIds.add(pet['id']) ||
        !{'It', 'Mushuk'}.contains(pet['type'])) {
      _invalid();
    }
  }
  var perDay = 0;
  for (final rate in price['rates']) {
    if (rate is! Map ||
        !petIds.remove(rate['animal_id']) ||
        !_positiveMoney(rate['daily_minor'])) {
      _invalid();
    }
    perDay += rate['daily_minor'] as int;
  }
  const day = Duration.microsecondsPerDay;
  final days = (end.difference(start).inMicroseconds + day - 1) ~/ day;
  final total = price['service_total_minor'], bps = price['commission_bps'];
  if (!_positiveMoney(total) ||
      total != perDay * days ||
      price['billable_days'] is! int ||
      days != price['billable_days'] ||
      bps is! int ||
      bps < 0 ||
      bps > 10000 ||
      price['commission_minor'] is! int ||
      price['commission_minor'] != (total * bps + 5000) ~/ 10000 ||
      price['rounding'] != 'nearest_minor_half_up') {
    _invalid();
  }
}

void checkBookingIdentity(BookingData data, String? expectedId) {
  if (!_id(data['id']) ||
      (expectedId != null && data['id'] != expectedId) ||
      !bookingStates.contains(data['status']) ||
      data['revision'] is! int ||
      data['revision'] < 0 ||
      !{'customer', 'sitter'}.contains(data['myRole']) ||
      data['snapshot'] is! Map ||
      data['history'] is! List) {
    _invalid();
  }
  _checkAgreement(data['snapshot']);
  _instant(data['replyDeadline']);
  var previous = -1;
  for (final event in data['history']) {
    if (event is! Map ||
        event['revision'] is! int ||
        event['revision'] <= previous ||
        event['revision'] > data['revision'] ||
        event['action'] is! String ||
        event['reason'] is! String ||
        !bookingStates.contains(event['status'])) {
      _invalid();
    }
    _instant(event['created']);
    previous = event['revision'];
  }
  final confirmations = data['confirmations'];
  if (confirmations != null) {
    for (final action in ['start', 'complete']) {
      if (confirmations is! Map ||
          confirmations[action] is! Map ||
          confirmations[action]['mine'] is! bool ||
          confirmations[action]['peer'] is! bool) {
        _invalid();
      }
    }
  }
}

void checkBookingCreated(BookingData data, BookingData pending) {
  checkBookingIdentity(data, null);
  final receipt = data['acknowledgement'];
  if (data['myRole'] != 'customer' ||
      receipt is! Map ||
      receipt['action'] != 'request' ||
      receipt['bookingId'] != data['id'] ||
      receipt['requestId'] != pending['requestId'] ||
      receipt['quoteId'] != pending['quoteId']) {
    _invalid();
  }
}

void checkBookingAction(BookingData data, String id, BookingData pending) {
  checkBookingIdentity(data, id);
  final action = pending['action'];
  if (!{'accept', 'reject', 'cancel'}.contains(action)) return;
  final receipt = data['acknowledgement'], body = pending['body'];
  if (receipt is! Map ||
      receipt['bookingId'] != id ||
      receipt['action'] != action ||
      receipt['requestId'] != body['requestId'] ||
      receipt['eventRevision'] != body['revision'] + 1 ||
      data['revision'] < receipt['eventRevision'] ||
      (receipt['eventAction'] != action &&
          receipt['eventAction'] != 'expire')) {
    _invalid();
  }
  final events = (data['history'] as List).where(
    (e) =>
        e is Map &&
        e['revision'] == receipt['eventRevision'] &&
        e['action'] == receipt['eventAction'],
  );
  if (events.length != 1) _invalid();
}

void checkBookingPage(BookingData data, String? before) {
  final rows = data['items'], next = data['nextCursor'];
  if (rows is! List || rows.length > 20 || !data.containsKey('nextCursor')) {
    _invalid();
  }
  if (next != null &&
      (next is! String ||
          !RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(next) ||
          (before != null && int.parse(next) >= int.parse(before)))) {
    _invalid();
  }
  final ids = <String>{};
  for (final row in rows) {
    if (row is! Map ||
        !_id(row['id']) ||
        !ids.add(row['id']) ||
        !bookingStates.contains(row['status']) ||
        row['peerName'] is! String ||
        !_services.contains(row['service']) ||
        !_positiveMoney(row['serviceTotalMinor']) ||
        row['pets'] is! List ||
        (row['pets'] as List).isEmpty ||
        (row['pets'] as List).length > 30 ||
        !_instant(row['endsAt']).isAfter(_instant(row['startsAt']))) {
      _invalid();
    }
    for (final pet in row['pets']) {
      if (pet is! Map ||
          pet['name'] is! String ||
          !{'It', 'Mushuk'}.contains(pet['type'])) {
        _invalid();
      }
    }
  }
}
