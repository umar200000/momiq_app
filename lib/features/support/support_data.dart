typedef SupportData = Map<String, dynamic>;

bool _number(Object? value) =>
    value is String && RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(value);
bool _id(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
bool _text(Object? value, int limit) =>
    value is String && value.runes.length <= limit;
bool _time(Object? value) =>
    value is String && value.length <= 64 && DateTime.tryParse(value) != null;
Never _invalid() => throw const FormatException('Invalid support response');

SupportData _ticket(Object? value) {
  if (value is! Map ||
      !_id(value['id']) ||
      !_text(value['subject'], 120) ||
      (value['subject'] as String).trim().isEmpty ||
      !const ['open', 'waiting_user', 'resolved'].contains(value['status']) ||
      value['revision'] is! int ||
      value['revision'] < 0 ||
      (value['bookingId'] != null && !_id(value['bookingId'])) ||
      !_time(value['updated'])) {
    _invalid();
  }
  return SupportData.from(value);
}

String? _cursor(SupportData data, String? before) {
  final value = data['nextCursor'];
  if (value != null &&
      (!_number(value) ||
          (before != null && int.parse(value) >= int.parse(before)))) {
    _invalid();
  }
  return value;
}

/// Validate the entire page before changing visible history or retry state.
SupportData supportList(SupportData data, {String? before}) {
  final rows = data['items'], legacy = data['legacyItems'] ?? [];
  if (rows is! List || rows.length > 20 || legacy is! List) _invalid();
  final items = <SupportData>[], ids = <String>{}, archive = <SupportData>[];
  for (final row in rows) {
    final item = _ticket(row);
    if (!ids.add(item['id'])) _invalid();
    items.add(item);
  }
  for (final row in legacy) {
    if (row is! Map || !_text(row['text'] ?? '', 4000)) _invalid();
    archive.add(SupportData.from(row));
  }
  final cursor = _cursor(data, before);
  if (cursor != null && items.isEmpty) _invalid();
  return {'items': items, 'legacyItems': archive, 'nextCursor': cursor};
}

SupportData supportThread(
  SupportData data, {
  String? id,
  String? before,
  int? minimumRevision,
}) {
  final ticket = _ticket(data['ticket']), rows = data['items'];
  if ((id != null && ticket['id'] != id) ||
      rows is! List ||
      rows.length > 20 ||
      (minimumRevision != null && ticket['revision'] < minimumRevision)) {
    _invalid();
  }
  final items = <SupportData>[];
  int previous = 0;
  for (final row in rows) {
    if (row is! Map ||
        !_number(row['id']) ||
        !const ['owner', 'support'].contains(row['authorRole']) ||
        !_text(row['text'], 4000) ||
        !_time(row['created']) ||
        (row['hasImage'] != null && row['hasImage'] is! bool)) {
      _invalid();
    }
    final current = int.parse(row['id']);
    if (current <= previous ||
        (before != null && current >= int.parse(before))) {
      _invalid();
    }
    previous = current;
    items.add(SupportData.from(row));
  }
  final cursor = _cursor(data, before), target = data['target'];
  if (cursor != null && (items.isEmpty || cursor != items.first['id'])) {
    _invalid();
  }
  if (target != null &&
      (target is! Map ||
          !const ['listing', 'review'].contains(target['kind']) ||
          !_text(target['id'], 120) ||
          (target['id'] as String).isEmpty ||
          !const ['report', 'appeal'].contains(target['purpose']))) {
    _invalid();
  }
  if (target != null) {
    final snapshot = target['snapshot'];
    if (snapshot != null && snapshot is! Map) _invalid();
    final media = snapshot?['media'];
    if (media != null &&
        (media is! Map ||
            media['slot'] is! String ||
            !RegExp(
              r'^(portrait|home:(0|[1-9][0-9]?))$',
            ).hasMatch(media['slot']) ||
            media['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(media['sha256']))) {
      _invalid();
    }
  }
  final video = data['videoReport'];
  if (video != null &&
      (target != null ||
          video is! Map ||
          video['id'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(video['id']) ||
          video['day'] is! String ||
          !RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(video['day']) ||
          !{'morning', 'evening'}.contains(video['slot']) ||
          ticket['topic'] != 'safety' ||
          ticket['bookingId'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(ticket['bookingId']))) {
    _invalid();
  }
  return {...data, 'ticket': ticket, 'items': items, 'nextCursor': cursor};
}
