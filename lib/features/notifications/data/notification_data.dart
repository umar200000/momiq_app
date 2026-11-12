typedef NoticeJson = Map<String, dynamic>;

bool noticeId(Object? value) =>
    value is String && RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(value);
bool noticeTime(Object? value) =>
    value is String &&
    DateTime.tryParse(value) != null &&
    RegExp(r'(?:Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(value);

/// Parse completely before replacing visible history or its pagination cursor.
NoticeJson notificationPage(NoticeJson data, {String? before}) {
  final items = data['items'],
      count = data['unreadCount'],
      cursor = data['nextCursor'];
  if (items is! List ||
      items.length > 20 ||
      count is! int ||
      count < 0 ||
      (cursor != null && !noticeId(cursor))) {
    throw const FormatException('Invalid notification page');
  }
  final result = <NoticeJson>[];
  int? previous = before == null ? null : int.parse(before);
  for (final item in items) {
    if (item is! Map ||
        !noticeId(item['id']) ||
        item['kind'] is! String ||
        item['targetId'] is! String ||
        item['status'] is! String ||
        item['reason'] is! String ||
        !noticeTime(item['created']) ||
        (item['readAt'] != null && !noticeTime(item['readAt']))) {
      throw const FormatException('Invalid notification');
    }
    final id = int.parse(item['id'] as String);
    if (previous != null && id >= previous) {
      throw const FormatException('Notification page is out of order');
    }
    previous = id;
    result.add(NoticeJson.from(item));
  }
  if (cursor != null && (result.isEmpty || cursor != result.last['id'])) {
    throw const FormatException('Invalid notification cursor');
  }
  return {'items': result, 'unreadCount': count, 'nextCursor': cursor};
}

/// Older servers return only ok; the caller retains the legacy estimate then.
NoticeJson? notificationReceipt(
  NoticeJson data,
  String id, {
  required bool allowLegacy,
}) {
  if (data['ok'] != true) throw const FormatException('Read not confirmed');
  final bound = data.containsKey('noticeId');
  if (bound ? data['noticeId'] != id : !allowLegacy) {
    throw const FormatException('Wrong notification acknowledgement');
  }
  if (!bound &&
      !data.containsKey('readAt') &&
      !data.containsKey('unreadCount')) {
    return null;
  }
  if (!noticeTime(data['readAt']) ||
      data['unreadCount'] is! int ||
      data['unreadCount'] < 0) {
    throw const FormatException('Invalid read receipt');
  }
  return data;
}
