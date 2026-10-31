import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/presentation/topup_history_page.dart';
import 'topup_history_test.dart' show HistoryApi;
import 'private_api_image_test.dart' show pixel;

class DelayedHistory extends CustomerApi {
  DelayedHistory() : super('TEST', 'owner');
  final calls = <String>[], pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    calls.add(path);
    final call = Completer<Map<String, dynamic>>();
    pending.add(call);
    return call.future;
  }
}

Map<String, dynamic> history(String reason) => {
  'items': [
    {
      'revision': 1,
      'event': 'request_info',
      'status': 'needs_info',
      'amountMinor': 123456,
      'qrVersion': 1,
      'reason': reason,
      'payerReference': 'TEST payer',
      'created': '2026-10-29T09:00:00Z',
    },
  ],
  'nextCursor': null,
};
Map<String, dynamic> corrections(String reason) => {
  'items': [
    {
      'id': 'a' * 32,
      'amountMinor': 100,
      'reason': reason,
      'created': '2026-10-29T09:00:00Z',
    },
  ],
  'nextCursor': null,
  'correctedMinor': 100,
};

void main() {
  setUp(() => CustomerApi.active = null);
  tearDown(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });
  Future<void> show(WidgetTester t, CustomerApi api, String id) => t.pumpWidget(
    MaterialApp(
      home: TopupHistoryPage(api: api, topupId: id),
    ),
  );
  Future<void> load(WidgetTester t, DelayedHistory api) async {
    await show(t, api, 'first');
    api.pending.last.complete(history('Private first receipt'));
    await t.pumpAndSettle();
  }

  testWidgets('old account history failure cannot clear next account loading', (
    t,
  ) async {
    final old = DelayedHistory(), next = DelayedHistory();
    await show(t, old, 'first');
    await show(t, next, 'second');
    old.pending.single.completeError(CustomerApiException('old error'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Tarix yuklanmadi'), findsNothing);
    next.pending.single.complete(history('New receipt'));
    await t.pumpAndSettle();
    expect(find.text('New receipt'), findsOneWidget);
  });

  testWidgets('receipt source change ignores pending image and corrections', (
    t,
  ) async {
    final api = DelayedHistory();
    await load(t, api);
    await t.tap(find.byKey(const ValueKey('topupCorrections')));
    await t.pump();
    await t.tap(find.text('Shu bosqichdagi chek'));
    await t.pump();
    await show(t, api, 'second');
    api.pending[1].complete(corrections('Private first correction'));
    api.pending[2].complete({'receipt': pixel});
    api.pending[3].complete(history('New receipt'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Private first'), findsNothing);
    expect(find.text('New receipt'), findsOneWidget);
    expect(find.textContaining('1.00 UZS'), findsNothing);
  });

  testWidgets(
    'source change removes owned receipt dialog and opens new receipt',
    (t) async {
      final api = DelayedHistory();
      await load(t, api);
      await t.tap(find.text('Shu bosqichdagi chek'));
      await t.pump();
      api.pending.last.complete({'receipt': pixel});
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await show(t, api, 'second');
      api.pending.last.complete(history('New receipt'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await t.tap(find.text('Shu bosqichdagi chek'));
      await t.pump();
      expect(api.calls.last, '/wallet/topups/second/history/1/receipt');
      api.pending.last.complete({'receipt': pixel});
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed refresh keeps history and correction totals without partial rows',
    (t) async {
      final api = DelayedHistory();
      await load(t, api);
      await t.tap(find.byKey(const ValueKey('topupCorrections')));
      await t.pump();
      api.pending.last.complete(corrections('Original correction'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('topupCorrections')));
      await t.pump();
      api.pending.last.complete({
        ...corrections('Changed'),
        'correctedMinor': 'invalid',
      });
      await t.pumpAndSettle();
      expect(find.textContaining('Original correction'), findsOneWidget);
      expect(find.textContaining('Changed'), findsNothing);
      expect(find.textContaining('1.00 UZS'), findsWidgets);
      final refresh = t.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final loading = refresh.onRefresh();
      api.pending.last.complete({
        ...history('Changed'),
        'items': [
          history('Changed')['items'][0],
          {'revision': 0},
        ],
      });
      await loading;
      await t.pumpAndSettle();
      expect(find.text('Private first receipt'), findsOneWidget);
      expect(find.text('Changed'), findsNothing);
      expect(find.textContaining('Tarix yuklanmadi'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'expired session cannot revive through a different receipt identifier',
    (t) async {
      final api = DelayedHistory();
      await load(t, api);
      CustomerApi.sessionVersion++;
      await show(t, api, 'second');
      await t.pumpAndSettle();
      expect(api.calls.length, 1);
      expect(find.text('Private first receipt'), findsNothing);
      expect(find.text('Hisobingizga qayta kiring.'), findsOneWidget);
    },
  );

  testWidgets('invalid receipt encoding can retry without changing history', (
    t,
  ) async {
    final api = DelayedHistory();
    await load(t, api);
    await t.tap(find.text('Shu bosqichdagi chek'));
    await t.pump();
    api.pending.last.complete({'receipt': '%%%'});
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Private first receipt'), findsOneWidget);
    await t.tap(find.text('Shu bosqichdagi chek'));
    await t.pump();
    api.pending.last.complete({'receipt': pixel});
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('$language receipt history fits narrow enlarged text', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      AppLanguage.current.value = language;
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: TopupHistoryPage(api: HistoryApi(), topupId: 'TEST'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('topupCorrections')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
