import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/notifications/presentation/notifications_page.dart';
import 'notification_lifecycle_test.dart' show PendingNotices;

const receipt = {
  'ok': true,
  'noticeId': '2',
  'readAt': '2026-11-11T09:00:00Z',
  'unreadCount': 0,
};

void main() {
  setUp(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });

  Future<NavigatorState> mount(WidgetTester t, PendingNotices api) async {
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    api.pending.last.complete(api.page());
    await t.pumpAndSettle();
    return t.state<NavigatorState>(find.byType(Navigator).first);
  }

  Future<void> cover(WidgetTester t, NavigatorState nav) async {
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final fails in [false, true]) {
    testWidgets(
      'late notice read cannot interrupt a newer route, failure=$fails',
      (t) async {
        final api = PendingNotices();
        final nav = await mount(t, api);
        await t.tap(find.byKey(const ValueKey('notice-2')));
        await t.pump();
        await cover(t, nav);
        if (fails) {
          api.pending.last.completeError(
            const FormatException('PRIVATE response'),
          );
        } else {
          api.pending.last.complete(receipt);
        }
        await t.pumpAndSettle();
        expect(find.text('NEXT PAGE'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(api.requests.where((p) => p.startsWith('POST')), hasLength(1));
        nav.pop();
        await t.pumpAndSettle();
        expect(find.text('O‘qilmagan: ${fails ? 2 : 0}'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('notice-2')));
        await t.pump();
        if (fails) api.pending.last.complete(receipt);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          api.requests.where((p) => p.startsWith('POST')),
          hasLength(fails ? 2 : 1),
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('retained row action on a covered page sends no read request', (
    t,
  ) async {
    final api = PendingNotices();
    final nav = await mount(t, api);
    final action = t
        .widget<ListTile>(find.byKey(const ValueKey('notice-2')))
        .onTap!;
    await cover(t, nav);
    action();
    await t.pump();
    expect(api.requests.where((p) => p.startsWith('POST')), isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final removed in [false, true]) {
    testWidgets(
      'retained row action cannot reopen a refreshed snapshot, removed=$removed',
      (t) async {
        final api = PendingNotices();
        await mount(t, api);
        final action = t
            .widget<ListTile>(find.byKey(const ValueKey('notice-2')))
            .onTap!;
        await t.tap(find.byIcon(Icons.refresh));
        await t.pump();
        api.pending.last.complete({
          ...api.page(reason: 'Updated reason'),
          if (removed) 'items': <Map<String, dynamic>>[],
        });
        await t.pumpAndSettle();
        action();
        await t.pump();
        expect(api.requests.where((p) => p.startsWith('POST')), isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        if (!removed) {
          await t.tap(find.byKey(const ValueKey('notice-2')));
          await t.pump();
          api.pending.last.complete(receipt);
          await t.pumpAndSettle();
          expect(find.text('Updated reason'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'a dialog result delivered beneath a newer route cannot open its target',
    (t) async {
      final api = PendingNotices()..kind = 'booking';
      final opened = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            api: api,
            bookingBuilder: (_, id) {
              opened.add(id);
              return const Scaffold(body: Text('BOOKING'));
            },
          ),
        ),
      );
      api.pending.last.complete(api.page());
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pump();
      api.pending.last.complete(receipt);
      await t.pumpAndSettle();
      final dialogRoute = ModalRoute.of(t.element(find.byType(AlertDialog)))!;
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      await cover(t, nav);
      nav.removeRoute(dialogRoute, true);
      await t.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('NEXT PAGE'), findsOneWidget);
      nav.pop();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Sahifani ochish'));
      await t.pumpAndSettle();
      expect(opened, [api.targetId]);
      expect(find.text('BOOKING'), findsOneWidget);
      expect(api.requests.where((p) => p.startsWith('POST')), hasLength(1));
    },
  );
}
