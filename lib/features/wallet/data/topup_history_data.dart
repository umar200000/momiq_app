typedef HistoryJson = Map<String, dynamic>;

bool _time(Object? value) =>
    value is String &&
    DateTime.tryParse(value) != null &&
    RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value);
bool _number(Object? value, {int min = 0}) => value is int && value >= min;

HistoryJson _page(HistoryJson page, bool corrections) {
  final items = page['items'], cursor = page['nextCursor'];
  if (items is! List ||
      items.length > 20 ||
      (cursor != null && (cursor is! String || cursor.isEmpty)) ||
      (corrections && !_number(page['correctedMinor']))) {
    throw const FormatException('Invalid history page');
  }
  final parsed = <HistoryJson>[], ids = <Object>{};
  for (final row in items) {
    if (row is! Map ||
        !_number(row['amountMinor'], min: 1) ||
        row['reason'] is! String ||
        !_time(row['created'])) {
      throw const FormatException('Invalid history entry');
    }
    final id = corrections ? row['id'] : row['revision'];
    if (corrections) {
      if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
        throw const FormatException('Invalid correction');
      }
    } else if (!_number(id) ||
        !_number(row['qrVersion'], min: 1) ||
        row['event'] is! String ||
        row['status'] is! String ||
        row['payerReference'] is! String) {
      throw const FormatException('Invalid history entry');
    }
    if (!ids.add(id!)) throw const FormatException('Duplicate history entry');
    parsed.add(HistoryJson.from(row));
  }
  if (cursor != null &&
      (parsed.isEmpty ||
          cursor !=
              '${corrections ? parsed.last['id'] : parsed.last['revision']}')) {
    throw const FormatException('Invalid history cursor');
  }
  return {...page, 'items': parsed};
}

HistoryJson topupHistoryPage(HistoryJson page) => _page(page, false);
HistoryJson topupCorrectionPage(HistoryJson page) => _page(page, true);
