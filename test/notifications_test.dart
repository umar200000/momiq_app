import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/notifications/presentation/notifications_page.dart';

class NoticeApi extends CustomerApi {
  NoticeApi() : super('test', 'owner');
  bool offline = false, readFails = false, empty = false;
  final Set<String> read = {};
  final List<String> requests = [];
  Map<String, dynamic> item(String id) => {
    'id': id,
    'kind': 'wallet_topup',
    'targetId': 'test-only',
    'status': 'rejected',
    'reason': 'TEST reason $id',
    'created': '2026-10-26T05:00:00Z',
    'readAt': read.contains(id) ? '2026-10-26T06:00:00Z' : null,
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    requests.add('$method $path');
    if (offline) throw CustomerApiException('Offline');
    if (method == 'POST') {
      if (readFails) throw CustomerApiException('Offline');
      read.add(path.split('/')[2]);
      return {'ok': true};
    }
    return {
      'items': empty
          ? []
          : path.contains('?')
          ? [item('1')]
          : [item('2')],
      'unreadCount': empty ? 0 : 2 - read.length,
      'nextCursor': empty || path.contains('?') ? null : '2',
    };
  }
}

void main() {
  testWidgets('history paginates and reading persists after reopening', (
    t,
  ) async {
    final api = NoticeApi();
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('notice-2')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('moreNotices')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('notice-1')), findsOneWidget);
    expect(api.requests, contains('GET /notifications?before=2'));
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    expect(api.read, {'2'});
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('Yopish'));
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(const ValueKey('noticeUnreadCount'))).data,
      contains('1'),
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    expect(
      api.requests.where((e) => e == 'POST /notifications/2/read').length,
      1,
    );
  });
  testWidgets('failed read preserves unread status and can be retried', (
    t,
  ) async {
    final api = NoticeApi()..readFails = true;
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    expect(api.read, isEmpty);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('noticeUnreadCount'))).data,
      contains('2'),
    );
    expect(find.byType(AlertDialog), findsNothing);
    api.readFails = false;
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    expect(api.read, {'2'});
  });
  testWidgets('offline history shows retry and successful empty state', (
    t,
  ) async {
    final api = NoticeApi()..offline = true;
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    await t.pumpAndSettle();
    expect(find.text('Qayta urinish'), findsOneWidget);
    api.offline = false;
    api.empty = true;
    await t.tap(find.text('Qayta urinish'));
    await t.pumpAndSettle();
    expect(find.textContaining('Hozircha bildirishnoma'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
