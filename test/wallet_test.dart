import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/presentation/wallet_page.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';

class WalletApi extends CustomerApi {
  WalletApi() : super('test', 'sitter');
  final sent = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'POST') {
      sent.add(Map.from(body!));
      if (fail) throw CustomerApiException('Connection lost');
      return {
        'topup': {'status': 'pending'},
      };
    }
    if (path.endsWith('/topups')) return {'topups': []};
    return {
      'balanceMinor': 0,
      'entries': [],
      'config': {
        'version': 2,
        'commissionBps': 1000,
        'minimumBalanceMinor': 1500000,
        'qrImage': png,
        'testOnly': true,
        'termsVersion': 'balance-no-refund-v1',
      },
    };
  }
}

void main() {
  test('money is exact in minor units and rejects ambiguous input', () {
    expect(parseWalletAmount('15000.01'), 1500001);
    expect(parseWalletAmount('0,10'), 10);
    expect(walletMoney(-1), '-0.01 so‘m');
    expect(walletMoney(-199), '-1.99 so‘m');
    for (final value in ['0', '-1', '1e3', '1.001', 'NaN', '1000000001', '']) {
      expect(() => parseWalletAmount(value), throwsFormatException);
    }
  });
  testWidgets(
    'requires consent and receipt, retries same request without adding pending funds',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WalletApi()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: WalletPage(
            api: api,
            pickReceipt: () async => base64Decode(png),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('submitTopup'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('topupAmount')),
        '15000.01',
      );
      await tester.tap(find.byKey(const ValueKey('pickTopupReceipt')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('nonRefundableConsent')),
      );
      await tester.tap(find.byKey(const ValueKey('nonRefundableConsent')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.sent.single['amountMinor'], 1500001);
      expect(api.sent.single['acceptNonRefundable'], isTrue);
      expect(api.sent.single['qrVersion'], 2);
      api.fail = false;
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.sent.length, 2);
      expect(api.sent[0]['requestId'], api.sent[1]['requestId']);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('walletBalance')),
        -500,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('walletBalance'))).data,
        '0 so‘m',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
