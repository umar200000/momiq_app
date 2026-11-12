import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_dashboard.dart';

Map<String, dynamic> dashboard(int count) => {
  'asOf': '2026-10-28T07:00:00+00:00',
  'profilePresent': true,
  'pendingCount': count,
  'activePetCount': 2,
  'activeBookingCount': 1,
  'disputedCount': 0,
  'balanceMinor': 1000000,
  'balanceEligible': false,
  'listings': [
    {
      'service': 'boarding',
      'status': 'approved',
      'reason': 'TEST review',
      'missing': <String>[],
      'testOnly': true,
    },
  ],
  'today': {'items': <Map<String, dynamic>>[], 'hasMore': false},
  'upcoming': {
    'items': [
      {
        'id': 'a' * 32,
        'service': 'boarding',
        'status': 'accepted',
        'startsAt': '2026-11-01T12:00:00Z',
        'endsAt': '2026-11-02T12:00:00Z',
        'peerName': 'TEST customer',
        'petNames': ['TEST Momi'],
        'overdue': false,
      },
    ],
    'hasMore': true,
  },
};

class DashboardApi extends CustomerApi {
  DashboardApi() : super('token', 'sitter');
  final replies = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    expect(method, 'GET');
    expect(path, '/me/dashboard');
    final c = Completer<Map<String, dynamic>>();
    replies.add(c);
    return c.future;
  }
}

Widget screen(
  DashboardApi api, {
  VoidCallback? orders,
  VoidCallback? listings,
  Future<void> Function()? wallet,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SitterDashboard(
        api: api,
        onOrders: orders ?? () {},
        onListings: listings ?? () {},
        onWallet: wallet ?? () async {},
        onProfile: () async {},
      ),
    ),
  ),
);
void main() {
  testWidgets(
    'dashboard never substitutes zero for loading or error; retry loads real counters',
    (t) async {
      final api = DashboardApi();
      await t.pumpWidget(screen(api));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('dashboardPending')), findsNothing);
      api.replies[0].completeError(StateError('offline'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboardError')), findsOneWidget);
      expect(find.byKey(const ValueKey('dashboardPending')), findsNothing);
      await t.tap(find.byKey(const ValueKey('refreshDashboard')));
      await t.pump();
      api.replies[1].complete(dashboard(3));
      await t.pumpAndSettle();
      expect(find.text('Yangi so‘rovlar: 3'), findsOneWidget);
      expect(
        find.textContaining('Faol parvarishdagi hayvonlar: 2'),
        findsOneWidget,
      );
      expect(
        find.textContaining('mavjud buyurtmalar davom etadi'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dashboardError')), findsNothing);
    },
  );
  testWidgets('failed refresh keeps last server data explicitly marked stale', (
    t,
  ) async {
    final api = DashboardApi();
    await t.pumpWidget(screen(api));
    api.replies[0].complete(dashboard(4));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('refreshDashboard')));
    await t.pump();
    api.replies[1].completeError(StateError('offline'));
    await t.pumpAndSettle();
    expect(find.text('Yangi so‘rovlar: 4'), findsOneWidget);
    expect(find.textContaining('oxirgi olingan'), findsOneWidget);
  });
  testWidgets('account switch and logout discard late dashboard responses', (
    t,
  ) async {
    final old = DashboardApi(), fresh = DashboardApi();
    await t.pumpWidget(screen(old));
    await t.pumpWidget(screen(fresh));
    fresh.replies[0].complete(dashboard(7));
    await t.pumpAndSettle();
    old.replies[0].complete(dashboard(999));
    await t.pumpAndSettle();
    expect(find.text('Yangi so‘rovlar: 7'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
    await t.tap(find.byKey(const ValueKey('refreshDashboard')));
    await t.pump();
    CustomerApi.sessionVersion++;
    fresh.replies[1].complete(dashboard(888));
    await t.pump();
    expect(find.textContaining('888'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'dashboard links open relevant sections and reload after wallet return',
    (t) async {
      final api = DashboardApi();
      int orders = 0, listings = 0, wallet = 0;
      await t.pumpWidget(
        screen(
          api,
          orders: () => orders++,
          listings: () => listings++,
          wallet: () async {
            wallet++;
          },
        ),
      );
      api.replies[0].complete(dashboard(1));
      await t.pumpAndSettle();
      await t.tap(find.text('Buyurtmalarni ochish'));
      expect(orders, 1);
      await t.ensureVisible(find.text('Balansni ochish'));
      await t.tap(find.text('Balansni ochish'));
      await t.pump();
      expect(wallet, 1);
      expect(api.replies.length, 2);
      api.replies[1].complete(dashboard(1));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('E’lonlarni ochish'));
      await t.pumpAndSettle();
      await t.tap(find.text('E’lonlarni ochish'));
      expect(listings, 1);
      expect(
        find.textContaining('TEST tasdiq shaxs tekshiruvi emas'),
        findsOneWidget,
      );
      expect(find.textContaining('TEST customer'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
