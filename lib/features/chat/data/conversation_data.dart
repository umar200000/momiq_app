typedef ConversationData = Map<String, dynamic>;
bool chatNumber(Object? value, {bool zero = false}) =>
    value is String &&
    RegExp(
      zero ? r'^(0|[1-9][0-9]{0,17})$' : r'^[1-9][0-9]{0,17}$',
    ).hasMatch(value);
bool chatIdentity(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
bool _text(Object? value, int max) =>
    value is String && value.runes.length <= max;
bool _time(Object? value) =>
    value is String && value.length <= 64 && DateTime.tryParse(value) != null;
Never _invalid() =>
    throw const FormatException('Invalid conversation response');
ConversationData chatMessage(Object? value, {String? requestId}) {
  if (value is! Map ||
      !chatNumber(value['id']) ||
      value['mine'] is! bool ||
      !const ['customer', 'sitter'].contains(value['senderRole']) ||
      !_text(value['text'], 4000) ||
      value['hasImage'] is! bool ||
      !_time(value['created']) ||
      (value['hidden'] != null && value['hidden'] is! bool) ||
      (requestId != null &&
          (value['mine'] != true || value['requestId'] != requestId))) {
    _invalid();
  }
  final result = ConversationData.from(value);
  if (result['hidden'] == true) {
    result['text'] = '';
    result['hasImage'] = false;
  }
  return result;
}

ConversationData chatSummary(Object? value, {String? id}) {
  if (value is! Map ||
      !chatIdentity(value['id']) ||
      (id != null && value['id'] != id) ||
      !_text(value['peerName'], 201) ||
      !const ['boarding', 'homeVisit', 'personal'].contains(value['service']) ||
      !const ['customer', 'sitter'].contains(value['myRole']) ||
      value['canSend'] is! bool ||
      value['blockedByMe'] is! bool ||
      value['blockRevision'] is! int ||
      value['blockRevision'] < 0 ||
      value['unreadCount'] is! int ||
      value['unreadCount'] < 0 ||
      !chatNumber(value['peerReadThrough'], zero: true) ||
      !chatNumber(value['peerDeliveredThrough'], zero: true)) {
    _invalid();
  }
  return {
    ...ConversationData.from(value),
    'lastMessage': value['lastMessage'] == null
        ? null
        : chatMessage(value['lastMessage']),
  };
}

ConversationData chatPage(
  ConversationData value, {
  required String id,
  String? before,
  String? after,
  String? changesAfter,
}) {
  final summary = chatSummary(value['conversation'], id: id),
      rows = value['items'],
      redacted = value['redactedIds'],
      change = value['changeCursor'];
  if (rows is! List ||
      rows.length > 30 ||
      value['hasMore'] is! bool ||
      redacted is! List ||
      redacted.length > 30 ||
      redacted.any((x) => !chatNumber(x)) ||
      !chatNumber(change, zero: true) ||
      (changesAfter != null && int.parse(change) < int.parse(changesAfter))) {
    _invalid();
  }
  final items = <ConversationData>[];
  int previous = 0;
  for (final row in rows) {
    final item = chatMessage(row), number = int.parse(row['id']);
    if (number <= previous ||
        (before != null && number >= int.parse(before)) ||
        (after != null && number <= int.parse(after))) {
      _invalid();
    }
    previous = number;
    items.add(item);
  }
  if (value['hasMore'] == true && items.length != 30) _invalid();
  return {
    ...value,
    'conversation': summary,
    'items': items,
    'redactedIds': List<String>.from(redacted),
  };
}

ConversationData chatInbox(ConversationData value, {String? before}) {
  final rows = value['items'], cursor = value['nextCursor'];
  if (rows is! List || rows.length > 30) _invalid();
  final items = <ConversationData>[], ids = <String>{};
  for (final row in rows) {
    final item = chatSummary(row);
    if (!ids.add(item['id'])) _invalid();
    items.add(item);
  }
  if (cursor != null) {
    if (cursor is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,17}):[1-9][0-9]{0,17}$').hasMatch(cursor) ||
        items.isEmpty) {
      _invalid();
    }
    if (before != null) {
      final now = cursor.split(':').map(int.parse).toList(),
          old = before.split(':').map(int.parse).toList();
      if (now[0] > old[0] || (now[0] == old[0] && now[1] >= old[1])) _invalid();
    }
  }
  return {'items': items, 'nextCursor': cursor};
}

ConversationData chatReport(
  Object? value, {
  String? messageId,
  String? reason,
}) {
  if (value is! Map ||
      !chatNumber(value['id']) ||
      !chatNumber(value['messageId']) ||
      !_text(value['reason'], 1000) ||
      !const ['open', 'dismissed', 'removed'].contains(value['status']) ||
      value['revision'] is! int ||
      value['revision'] < 0 ||
      !_time(value['created']) ||
      (value['reviewReason'] != null && !_text(value['reviewReason'], 1000)) ||
      (messageId != null && value['messageId'] != messageId) ||
      (reason != null && value['reason'] != reason)) {
    _invalid();
  }
  return ConversationData.from(value);
}

ConversationData chatReportPage(ConversationData value, {String? before}) {
  final rows = value['items'], cursor = value['nextCursor'];
  if (rows is! List ||
      rows.length > 20 ||
      (cursor != null && !chatNumber(cursor))) {
    _invalid();
  }
  final items = <ConversationData>[];
  int? previous = before == null ? null : int.parse(before);
  for (final row in rows) {
    final item = chatReport(row), number = int.parse(item['id']);
    if (previous != null && number >= previous) _invalid();
    previous = number;
    items.add(item);
  }
  if (cursor != null && (items.isEmpty || cursor != items.last['id'])) {
    _invalid();
  }
  return {'items': items, 'nextCursor': cursor};
}
