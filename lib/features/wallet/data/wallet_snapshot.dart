import 'dart:convert';

typedef WalletJson = Map<String, dynamic>;

void _require(bool valid) {
  if (!valid) throw const FormatException('Invalid wallet response');
}

bool _id(dynamic value) =>
    value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
bool _integer(dynamic value, int minimum) => value is int && value >= minimum;

WalletJson _object(dynamic value) {
  _require(value is Map<String, dynamic>);
  return Map<String, dynamic>.from(value as Map);
}

DateTime _created(WalletJson row) {
  final value = row['created'];
  _require(value is String && RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value));
  final date = DateTime.tryParse(value as String);
  _require(date != null);
  return date!;
}

bool _older(WalletJson row, WalletJson previous) {
  final date = _created(row).compareTo(_created(previous));
  return date < 0 ||
      (date == 0 &&
          (row['id'] as String).compareTo(previous['id'] as String) < 0);
}

WalletJson walletPaymentConfig(dynamic value) {
  final config = _object(value);
  _require(_integer(config['version'], 1));
  _require(_integer(config['minimumBalanceMinor'], 0));
  _require(
    _integer(config['commissionBps'], 0) && config['commissionBps'] <= 10000,
  );
  _require(config['currency'] == null || config['currency'] == 'UZS');
  _require(config['provider'] == null || config['provider'] == 'paynet_xolis');
  _require(config['qrActive'] is bool && config['testOnly'] is bool);
  _require(config['termsVersion'] == 'balance-no-refund-v1');
  _require(
    config['unusedBalanceRefundable'] == null ||
        config['unusedBalanceRefundable'] == false,
  );
  _require(config['recipientName'] is String);
  _require(
    config['paymentInstructions'] == null ||
        config['paymentInstructions'] is String,
  );
  final qr = config['qrImage'];
  _require(qr == null || qr is String);
  if (qr != null) _require(base64Decode(qr as String).isNotEmpty);
  if (config['qrActive'] == true) {
    _require(
      qr != null && (config['recipientName'] as String).trim().isNotEmpty,
    );
  }
  return config;
}

/// Validate the complete response before publishing any financial UI state.
WalletJson walletSnapshot(WalletJson value) {
  final config = walletPaymentConfig(value['config']);
  _require(_integer(value['balanceMinor'], 0));
  _require(value['currency'] == null || value['currency'] == 'UZS');
  if (value.containsKey('minimumBalanceMinor')) {
    _require(value['minimumBalanceMinor'] == config['minimumBalanceMinor']);
  }
  if (value.containsKey('balanceEligible')) {
    _require(
      value['balanceEligible'] ==
          (value['balanceMinor'] >= config['minimumBalanceMinor']),
    );
  }
  final entries = value['entries'];
  _require(entries is List && entries.length <= 50);
  final parsed = <WalletJson>[];
  final ids = <String>{};
  for (final raw in entries as List) {
    final row = _object(raw);
    _require(_id(row['id']) && ids.add(row['id']));
    _require(row['amountMinor'] is int && row['amountMinor'] != 0);
    _require(_integer(row['balanceAfter'], 0));
    _require(row['kind'] is String && row['reason'] is String);
    _require(row['topupId'] == null || _id(row['topupId']));
    _created(row);
    if (parsed.isNotEmpty) _require(_older(row, parsed.last));
    parsed.add(row);
  }
  return {...value, 'config': config, 'entries': parsed};
}

/// A rejected page never advances the cursor or partially appends rows.
WalletJson walletTopupPage(
  WalletJson value, {
  List<dynamic> previous = const [],
  String? cursor,
}) {
  final items = value['topups'];
  _require(items is List && items.length <= 20);
  final ids = previous.map((row) => row['id'] as String).toSet();
  WalletJson? last = previous.isEmpty ? null : _object(previous.last);
  final parsed = <WalletJson>[];
  for (final raw in items as List) {
    final row = _object(raw);
    _require(_id(row['id']) && ids.add(row['id']));
    _require(
      _integer(row['amountMinor'], 1) && row['amountMinor'] <= 100000000000,
    );
    _require(_integer(row['revision'], 0));
    _require(
      {'pending', 'approved', 'needs_info', 'rejected'}.contains(row['status']),
    );
    _require(row['reviewReason'] == null || row['reviewReason'] is String);
    _require(row['currency'] == null || row['currency'] == 'UZS');
    _created(row);
    if (last != null) _require(_older(row, last));
    parsed.add(row);
    last = row;
  }
  final next = value['nextCursor'];
  _require(
    next == null ||
        (_id(next) &&
            next != cursor &&
            parsed.length == 20 &&
            next == parsed.last['id']),
  );
  return {'topups': parsed, 'nextCursor': next};
}
