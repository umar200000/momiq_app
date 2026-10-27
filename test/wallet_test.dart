import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/presentation/wallet_page.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';

class MemoryDraft extends WalletDraftStorage {
  Map<String, dynamic>? data;
  bool failWrite = false, failClear = false;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>?> read() async => data == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(jsonEncode(data)));
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (failWrite) throw StateError('Storage unavailable');
    if (gate != null) await gate!.future;
    data = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Storage unavailable');
    data = null;
  }
}

class WalletApi extends CustomerApi {
  WalletApi() : super('test', 'sitter');
  final sent = <Map<String, dynamic>>[];
  bool fail = false;
  bool qrActive = true;
  int qrVersion = 2;
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
        'version': qrVersion,
        'commissionBps': 1000,
        'minimumBalanceMinor': 1500000,
        'qrImage': png,
        'qrActive': qrActive,
        'recipientName': 'TEST recipient',
        'testOnly': true,
        'termsVersion': 'balance-no-refund-v1',
      },
    };
  }
}

class AmendmentApi extends WalletApi {
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add('$method $path');
    if (method == 'GET' && path == '/wallet/topups/test') {
      return {
        'topup': {
          'id': 'test',
          'revision': 1,
          'status': 'needs_info',
          'amountMinor': 100,
          'payerReference': 'TEST-original',
          'paidAt': null,
        },
      };
    }
    if (method == 'GET' && path.endsWith('/receipt')) {
      return {
        'receipt': png,
        'revision': 1,
        'paymentSnapshot': {
          'version': 2,
          'qrImage': png,
          'recipientName': 'TEST old recipient',
          'testOnly': true,
        },
      };
    }
    return super.request(method, path, body);
  }
}

void main() {
  testWidgets(
    'clarification keeps original evidence version and retry id without offering a new payment',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = AmendmentApi()..fail = true;
      final draft = MemoryDraft();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WalletPage(
                      api: api,
                      topupId: 'test',
                      draftStorage: draft,
                    ),
                  ),
                ),
                child: const Text('Open amendment'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open amendment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Qayta pul o‘tkazmang'), findsOneWidget);
      expect(find.byKey(const ValueKey('startTopup')), findsNothing);
      expect(find.bySemanticsLabel('Paynet Xolis QR'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('topupAmount')), '2');
      await tester.tap(find.byKey(const ValueKey('nonRefundableConsent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('submitTopup')));
      await tester.pumpAndSettle();
      expect(api.paths, contains('POST /wallet/topups/test/amend'));
      expect(api.sent.single['revision'], 1);
      expect(api.sent.single['amountMinor'], 200);
      final requestId = api.sent.single['requestId'];
      await tester.pageBack();
      await tester.pumpAndSettle();
      api.qrVersion = 9;
      api.fail = false;
      await tester.tap(find.text('Open amendment'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('nonRefundableConsent')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('nonRefundableConsent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('submitTopup')));
      await tester.pumpAndSettle();
      expect(api.sent.last['requestId'], requestId);
      expect(api.sent.last['qrVersion'], 2);
      expect(api.sent.last['revision'], 1);
      expect(draft.data, isNull);
      expect(find.text('Open amendment'), findsOneWidget);
    },
  );
  testWidgets('QR stays hidden until its draft is durably saved', (
    tester,
  ) async {
    final draft = MemoryDraft()..gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: WalletPage(api: WalletApi(), draftStorage: draft),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('startTopup')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('topupAmount')), findsNothing);
    draft.gate!.complete();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('topupAmount')),
      250,
    );
    expect(find.byKey(const ValueKey('topupAmount')), findsOneWidget);
  });
  testWidgets(
    'storage failure prevents starting a payment and can be retried',
    (tester) async {
      final draft = MemoryDraft()..failWrite = true;
      final api = WalletApi();
      await tester.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, draftStorage: draft),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('startTopup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topupAmount')), findsNothing);
      expect(api.sent, isEmpty);
      draft.failWrite = false;
      await tester.tap(find.byKey(const ValueKey('startTopup')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('topupAmount')),
        250,
      );
      expect(find.byKey(const ValueKey('topupAmount')), findsOneWidget);
    },
  );
  testWidgets('paused QR does not invite new payments', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletPage(
          api: WalletApi()..qrActive = false,
          draftStorage: MemoryDraft(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topupAmount')), findsNothing);
    expect(find.byKey(const ValueKey('submitTopup')), findsNothing);
    expect(find.textContaining('QR orqali yangi to‘lovlar'), findsOneWidget);
  });
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
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = WalletApi()..fail = true;
      final draft = MemoryDraft();
      await tester.pumpWidget(
        MaterialApp(
          home: WalletPage(
            api: api,
            draftStorage: draft,
            pickReceipt: () async => base64Decode(png),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('submitTopup'));
      await tester.tap(find.byKey(const ValueKey('startTopup')));
      await tester.pumpAndSettle();
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
      expect(api.sent, isEmpty);
      await tester.ensureVisible(find.byKey(const ValueKey('topupReference')));
      await tester.enterText(
        find.byKey(const ValueKey('topupReference')),
        'TEST-REFERENCE-001',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.sent.single['payerReference'], 'TEST-REFERENCE-001');
      expect(api.sent.single['amountMinor'], 1500001);
      expect(api.sent.single['acceptNonRefundable'], isTrue);
      expect(api.sent.single['qrVersion'], 2);
      expect(draft.data!['requestId'], api.sent.single['requestId']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      api.qrVersion = 9;
      await tester.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, draftStorage: draft),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('topupAmount')))
            .controller!
            .text,
        '15000.01',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('nonRefundableConsent')),
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('nonRefundableConsent')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('nonRefundableConsent')));
      await tester.pumpAndSettle();
      api.fail = false;
      draft.failClear = true;
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.sent.length, 2);
      expect(
        find.textContaining('Chek yuborildi — qoralamani tozalash'),
        findsOneWidget,
      );
      draft.failClear = false;
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.sent.length, 2);
      expect(api.sent[0]['requestId'], api.sent[1]['requestId']);
      expect(api.sent[1]['qrVersion'], 2);
      expect(api.sent[1]['payerReference'], 'TEST-REFERENCE-001');
      expect(draft.data, isNull);
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
