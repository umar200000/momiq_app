typedef DisputeData = Map<String, dynamic>;
bool _text(Object? v, int limit) => v is String && v.runes.length <= limit;
bool _number(Object? v) =>
    v is String && RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(v);
bool _time(Object? v) =>
    v is String && v.length <= 64 && DateTime.tryParse(v) != null;
bool _integer(Object? v, {int min = 0}) => v is int && v >= min;
Never _bad() => throw const FormatException('Invalid dispute response');

DisputeData disputeData(
  DisputeData value,
  String bookingId, {
  String? before,
  DisputeData? request,
}) {
  final rows = value['items'],
      cursor = value['nextCursor'],
      caseData = value['case'];
  if (value['bookingId'] != bookingId ||
      !_integer(value['bookingRevision']) ||
      ![
        'pending',
        'accepted',
        'active',
        'completed',
        'cancelled',
        'rejected',
        'expired',
        'disputed',
      ].contains(value['bookingStatus']) ||
      !_time(value['serverNow']) ||
      ![
        'waiting',
        'contact_reminder',
        'complaint_available',
        'not_applicable',
      ].contains(value['stage']) ||
      [
        'canReportNoShow',
        'canReportService',
        'canAddEvidence',
      ].any((key) => value[key] is! bool) ||
      !_integer(value['refundableMinor']) ||
      value['customerServicePaymentRefunded'] != false ||
      rows is! List ||
      rows.length > 20 ||
      (cursor != null && !_number(cursor))) {
    _bad();
  }
  if (caseData != null) {
    if (caseData is! Map ||
        caseData['bookingId'] != bookingId ||
        !['no_show', 'service'].contains(caseData['kind']) ||
        !['open', 'resolved'].contains(caseData['status']) ||
        !['accepted', 'active'].contains(caseData['priorStatus']) ||
        !_integer(caseData['revision'], min: 1) ||
        !_time(caseData['created']) ||
        !_time(caseData['deadline']) ||
        caseData['overdue'] is! bool ||
        !_integer(caseData['refundMinor'])) {
      _bad();
    }
    if (caseData['status'] == 'resolved' &&
        (!_time(caseData['resolvedAt']) ||
            ![
              'not_started',
              'continue',
              'cancel_service',
            ].contains(caseData['outcome']) ||
            !_text(caseData['reason'], 1000) ||
            (caseData['reason'] as String).trim().isEmpty)) {
      _bad();
    }
    if (value['canReportNoShow'] == true ||
        value['canReportService'] == true ||
        (value['canAddEvidence'] == true && caseData['status'] != 'open')) {
      _bad();
    }
  } else if (rows.isNotEmpty || value['canAddEvidence'] == true) {
    _bad();
  }
  final items = <DisputeData>[];
  var previous = 0;
  for (final row in rows) {
    if (row is! Map ||
        !_number(row['id']) ||
        !_integer(row['revision'], min: 1) ||
        row['mine'] is! bool ||
        !['customer', 'sitter', 'admin'].contains(row['role']) ||
        !['report', 'evidence', 'resolve'].contains(row['action']) ||
        !_text(row['text'], 4000) ||
        row['hasImage'] is! bool ||
        !_time(row['created'])) {
      _bad();
    }
    final id = int.parse(row['id']);
    if (id <= previous ||
        (before != null && id >= int.parse(before)) ||
        row['revision'] > caseData['revision']) {
      _bad();
    }
    previous = id;
    items.add(DisputeData.from(row));
  }
  if (cursor != null && (items.length != 20 || cursor != items.first['id'])) {
    _bad();
  }
  if (request != null) {
    final receipt = value['acknowledgement'];
    if (caseData == null ||
        receipt is! Map ||
        receipt['requestId'] != request['requestId'] ||
        receipt['action'] != request['action'] ||
        receipt['kind'] != request['kind'] ||
        !_number(receipt['messageId']) ||
        receipt['revision'] != request['revision'] + 1 ||
        receipt['revision'] > caseData['revision']) {
      _bad();
    }
    for (final message in items.where(
      (item) => item['id'] == receipt['messageId'],
    )) {
      if (message['mine'] != true ||
          message['action'] != request['action'] ||
          message['revision'] != receipt['revision'] ||
          message['text'] != (request['text'] as String).trim() ||
          message['hasImage'] != (request['image'] != null)) {
        _bad();
      }
    }
  }
  return {
    ...value,
    'case': caseData == null ? null : DisputeData.from(caseData),
    'items': items,
  };
}

DisputeData? disputeDraft(DisputeData? value) {
  if (value == null) return null;
  if (value.length != 7 ||
      !value.keys.toSet().containsAll([
        'action',
        'kind',
        'revision',
        'bookingRevision',
        'text',
        'image',
        'requestId',
      ]) ||
      !['report', 'evidence'].contains(value['action']) ||
      !['no_show', 'service'].contains(value['kind']) ||
      !_integer(value['revision']) ||
      !_integer(value['bookingRevision']) ||
      !_text(value['text'], 4000) ||
      (value['text'] as String).trim().isEmpty ||
      (value['image'] != null && !_text(value['image'], 4 * 1024 * 1024)) ||
      value['requestId'] is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(value['requestId'])) {
    _bad();
  }
  return Map.of(value);
}
