import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/notifications/presentation/notifications_page.dart';
import 'package:momiq_app/features/listings/presentation/listings_panel.dart';
import 'notifications_test.dart' show NoticeApi;
import 'package:momiq_app/features/notifications/data/notification_data.dart';

class PendingNotices extends NoticeApi {
  final pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    requests.add('$method $path');
    final call = Completer<Map<String, dynamic>>();
    pending.add(call);
    return call.future;
  }

  Map<String, dynamic> page({String reason = 'Private old account'}) => {
    'items': [
      {...item('2'), 'reason': reason},
    ],
    'unreadCount': 2,
    'nextCursor': null,
  };
}

void main() {
  setUp(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });
  Future<void> show(WidgetTester t, CustomerApi api) =>
      t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
  Future<void> loaded(WidgetTester t, PendingNotices api) async {
    await show(t, api);
    api.pending.last.complete(api.page());
    await t.pumpAndSettle();
  }

  Future<void> read(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pump();
  }

  const receipt = {
    'ok': true,
    'noticeId': '2',
    'readAt': '2026-10-29T09:00:00Z',
    'unreadCount': 7,
  };

  test('hosted read requires the requested ID, pages advance strictly', () {
    final legacy = Map<String, dynamic>.of(receipt)..remove('noticeId');
    expect(
      () => notificationReceipt(legacy, '2', allowLegacy: false),
      throwsFormatException,
    );
    expect(notificationReceipt(legacy, '2', allowLegacy: true), legacy);
    final api = PendingNotices();
    for (final ids in [
      ['2'],
      ['3'],
      ['1', '2'],
      ['1', '1'],
    ]) {
      expect(
        () => notificationPage({
          ...api.page(),
          'items': ids.map(api.item).toList(),
        }, before: '2'),
        throwsFormatException,
      );
    }
    expect(notificationPage(api.page(), before: '3')['items'], hasLength(1));
  });

  testWidgets(
    'old page error cannot clear new account loading or expose history',
    (t) async {
      final old = PendingNotices(), next = PendingNotices();
      await show(t, old);
      await show(t, next);
      old.pending.single.completeError(CustomerApiException('old failure'));
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Qayta urinib'), findsNothing);
      next.pending.single.complete(next.page(reason: 'New account'));
      await t.pumpAndSettle();
      expect(find.textContaining('New account'), findsOneWidget);
      expect(find.textContaining('Private old account'), findsNothing);
    },
  );

  testWidgets('late read receipt cannot mark new account row read', (t) async {
    final old = PendingNotices(), next = PendingNotices();
    await loaded(t, old);
    await read(t);
    await show(t, next);
    next.pending.single.complete(next.page(reason: 'New account'));
    old.pending.last.complete(receipt);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('O‘qilmagan: 2'), findsOneWidget);
    expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);
  });

  testWidgets(
    'server read receipt supplies count and malformed acknowledgement is retryable',
    (t) async {
      final api = PendingNotices();
      await loaded(t, api);
      await read(t);
      api.pending.last.complete({'ok': true, 'unreadCount': 0});
      await t.pumpAndSettle();
      expect(find.text('O‘qilmagan: 2'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await read(t);
      api.pending.last.complete({...receipt, 'noticeId': '1'});
      await t.pumpAndSettle();
      expect(find.text('O‘qilmagan: 2'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await read(t);
      api.pending.last.complete(receipt);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('Yopish'));
      await t.pumpAndSettle();
      expect(find.text('O‘qilmagan: 7'), findsOneWidget);
      expect(find.byIcon(Icons.drafts_outlined), findsOneWidget);
      await read(t);
      await t.pumpAndSettle();
      expect(api.requests.where((r) => r.startsWith('POST')).length, 3);
    },
  );

  testWidgets('malformed refreshed page leaves previous history intact', (
    t,
  ) async {
    final api = PendingNotices();
    await loaded(t, api);
    await t.tap(find.byIcon(Icons.refresh));
    await t.pump();
    api.pending.last.complete({
      ...api.page(),
      'items': [
        api.item('1'),
        {...api.item('2'), 'created': 'broken'},
      ],
    });
    await t.pumpAndSettle();
    expect(find.textContaining('Private old account'), findsOneWidget);
    expect(find.byKey(const ValueKey('notice-1')), findsNothing);
    expect(find.text('O‘qilmagan: 2'), findsOneWidget);
    expect(find.textContaining('Bildirishnomalar yuklanmadi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'account rebind removes only its old dialog and permits new notices',
    (t) async {
      final old = PendingNotices(), next = PendingNotices();
      await loaded(t, old);
      await read(t);
      old.pending.last.complete(receipt);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await show(t, next);
      next.pending.single.complete(next.page(reason: 'New account'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Private old account'), findsNothing);
      await read(t);
      next.pending.last.complete(receipt);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('New account'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'expired session ignores pending acknowledgement and hides old history on rebuild',
    (t) async {
      final api = PendingNotices();
      await loaded(t, api);
      await read(t);
      CustomerApi.sessionVersion++;
      api.pending.last.complete(receipt);
      await show(t, api);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Private old account'), findsNothing);
      expect(find.text('Hisobingizga qayta kiring.'), findsOneWidget);
    },
  );

  testWidgets('unknown future notice has generic title and no destination', (
    t,
  ) async {
    final api = NoticeApi()..kind = 'future_kind';
    await show(t, api);
    await t.pumpAndSettle();
    expect(find.text('Bildirishnoma'), findsOneWidget);
    await read(t);
    await t.pumpAndSettle();
    expect(find.text('Sahifani ochish'), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('listing notice uses its captured authenticated listing store', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = PendingNotices()
      ..kind = 'listing'
      ..targetId = 'boarding';
    await loaded(t, api);
    await read(t);
    api.pending.last.complete(receipt);
    await t.pumpAndSettle();
    await t.tap(find.text('Sahifani ochish'));
    await t.pump();
    expect(api.requests.last, 'GET /me/listings');
    api.pending.last.complete({'listings': [], '_revision': 0});
    await t.pumpAndSettle();
    expect(
      t.widget<ListingsPanel>(find.byType(ListingsPanel)).store!.api,
      same(api),
    );
    expect(t.takeException(), isNull);
  });

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('$language no-show notice and dialog fit narrow large text', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      AppLanguage.current.value = language;
      final api = NoticeApi()
        ..kind = 'booking'
        ..status = 'complaint_available';
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: NotificationsPage(api: api),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('notice-2')));
      await read(t);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
