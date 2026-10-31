import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/presentation/wallet_page.dart';
import 'wallet_test.dart' show MemoryDraft, WalletApi, png;

class GatedWallet extends WalletApi {
  GatedWallet(this.value);
  final int value;
  final reads = <String>[];
  Completer<void>? gate;
  bool mismatch = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    reads.add('$method $path');
    if (method == 'GET' && path == '/wallet' && gate != null) {
      await gate!.future;
    }
    final data = await super.request(method, path, body);
    if (method == 'GET' && path == '/wallet') data['balanceMinor'] = value;
    if (method == 'POST' && mismatch) {
      data['acknowledgement']['receiptSha256'] = 'f' * 64;
    }
    return data;
  }
}

Future<MemoryDraft> evidence(WalletApi api) async {
  final config = (await api.request('GET', '/wallet'))['config'];
  return MemoryDraft()
    ..data = {
      'formatVersion': 1,
      'amount': '1',
      'payerReference': 'TEST',
      'receipt': png,
      'config': config,
      'receiptPickPending': false,
      'requestId': null,
    };
}

void main() {
  testWidgets(
    'late wallet load cannot fetch or show private data on a replacement account',
    (t) async {
      final old = GatedWallet(123400)..gate = Completer<void>(),
          fresh = GatedWallet(678900);
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: old, draftStorage: MemoryDraft()),
        ),
      );
      await t.pump();
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: fresh, draftStorage: MemoryDraft()),
        ),
      );
      await t.pumpAndSettle();
      old.gate!.complete();
      await t.pumpAndSettle();
      expect(old.reads, ['GET /wallet']);
      expect(fresh.reads, ['GET /wallet', 'GET /wallet/topups']);
      expect(find.textContaining('6789'), findsWidgets);
      expect(find.textContaining('1234'), findsNothing);
    },
  );
  testWidgets(
    'an expired wallet cannot send evidence after delayed draft persistence',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = GatedWallet(0), store = await evidence(api);
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, draftStorage: store),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('nonRefundableConsent')));
      await t.pumpAndSettle();
      store.gate = Completer<void>();
      await t.tap(find.byKey(const ValueKey('submitTopup')));
      await t.pump();
      CustomerApi.sessionVersion++;
      store.gate!.complete();
      await t.pump();
      expect(api.sent, isEmpty);
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, topupId: 'other', draftStorage: store),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Sessiya o‘zgardi'), findsOneWidget);
      expect(api.reads.where((v) => v.contains('/other')), isEmpty);
    },
  );
  testWidgets(
    'a mismatched receipt retains the exact top-up attempt until valid replay',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = GatedWallet(0)..mismatch = true, store = await evidence(api);
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, draftStorage: store),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('nonRefundableConsent')));
      await t.pumpAndSettle();
      final submit = find.byKey(const ValueKey('submitTopup'));
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(store.data!['requestId'], api.sent.single['requestId']);
      expect(store.data!['submissionPending'], true);
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('topupAmount'))).enabled,
        false,
      );
      api.mismatch = false;
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(api.sent.length, 2);
      expect(api.sent.last, api.sent.first);
      expect(store.data, isNull);
    },
  );
}
