import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/notifications/presentation/notifications_page.dart';
import 'package:momiq_app/features/wallet/presentation/topup_history_page.dart';
import 'package:momiq_app/features/care/presentation/booking_care_page.dart';
import 'package:momiq_app/features/chat/presentation/conversation_page.dart';
import 'booking_care_test.dart' show CareApi;
import 'conversation_test.dart' show ChatApi, ChatDraft;
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';

class NoticeApi extends CustomerApi {
  NoticeApi() : super('test', 'owner');
  bool offline = false, readFails = false, empty = false;
  String targetId = '1234567890abcdef1234567890abcdef';
  bool historyGone = false;
  String kind = 'wallet_topup';
  String status = 'rejected';
  final Set<String> read = {};
  final List<String> requests = [];
  Map<String, dynamic> item(String id) => {
    'id': id,
    'kind': kind,
    'targetId': targetId,
    'status': status,
    'reason': 'TEST reason $id',
    'created': '2026-10-26T05:00:00Z',
    'readAt': read.contains(id) ? '2026-10-26T06:00:00Z' : null,
  };
  final careApi = CareApi();
  final chatApi = ChatApi();
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    requests.add('$method $path');
    if (offline) throw CustomerApiException('Offline');
    if (path.startsWith('/bookings/')) {
      return careApi.request(method, path, body);
    }
    if (path.startsWith('/conversations/')) {
      return chatApi.request(method, path, body);
    }
    if (method == 'POST') {
      if (readFails) throw CustomerApiException('Offline');
      read.add(path.split('/')[2]);
      return {'ok': true};
    }
    if (path.startsWith('/wallet/topups/')) {
      if (historyGone) throw CustomerApiException('Not found');
      return {'items': [], 'nextCursor': null};
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
  for (final entry in {
    'contact_reminder': 'Boshlanishni tekshiring',
    'complaint_available': 'Kelmaslik bo‘yicha murojaat qilish mumkin',
  }.entries) {
    testWidgets('${entry.key} opens booking without a status mutation', (
      t,
    ) async {
      final api = NoticeApi()
        ..kind = 'booking'
        ..status = entry.key;
      await t.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            api: api,
            bookingBuilder: (_, id) => Scaffold(body: Text('Booking $id')),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Sahifani ochish'));
      await t.pumpAndSettle();
      expect(find.text('Booking ${api.targetId}'), findsOneWidget);
      expect(api.requests.where((r) => r.startsWith('POST')), [
        'POST /notifications/2/read',
      ]);
    });
  }
  for (final kind in ['care', 'conversation']) {
    testWidgets('$kind notice opens authenticated internal target only', (
      t,
    ) async {
      final api = NoticeApi()..kind = kind;
      final care = BookingCareController(
        api,
        api.targetId,
        storage: ChatDraft(),
      );
      final chat = ConversationController(
        api,
        api.targetId,
        storage: ChatDraft(),
      );
      addTearDown(care.dispose);
      addTearDown(chat.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            api: api,
            careBuilder: (source, id) =>
                BookingCarePage(api: source, bookingId: id, controller: care),
            conversationBuilder: (source, id) => ConversationPage(
              api: source,
              conversationId: id,
              controller: chat,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Sahifani ochish'));
      await t.pumpAndSettle();
      if (kind == 'care') {
        expect(
          t.widget<BookingCarePage>(find.byType(BookingCarePage)).bookingId,
          api.targetId,
        );
        expect(api.requests, contains('GET /bookings/${api.targetId}/care'));
      } else {
        expect(
          t
              .widget<ConversationPage>(find.byType(ConversationPage))
              .conversationId,
          api.targetId,
        );
        expect(
          api.requests,
          contains('GET /conversations/${api.targetId}/messages'),
        );
      }
      expect(api.read, contains('2'));
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$kind notice rejects external URL destinations', (t) async {
      final api = NoticeApi()
        ..kind = kind
        ..targetId = 'https://untrusted.invalid/private';
      await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pumpAndSettle();
      expect(find.text('Sahifani ochish'), findsNothing);
      expect(api.requests.any((p) => p.contains('untrusted')), false);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'booking notice marks read then opens only its validated booking ID',
    (t) async {
      final api = NoticeApi()..kind = 'booking';
      await t.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            api: api,
            bookingBuilder: (source, id) {
              expect(identical(source, api), isTrue);
              return Scaffold(body: Text('TEST booking $id'));
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Buyurtma · Rad etilgan'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pumpAndSettle();
      expect(api.read, contains('2'));
      await t.tap(find.text('Sahifani ochish'));
      await t.pumpAndSettle();
      expect(find.text('TEST booking ${api.targetId}'), findsOneWidget);
      expect(api.requests.any((p) => p.contains('/wallet/')), isFalse);
    },
  );
  testWidgets(
    'wallet notice opens only its receipt history and missing target can retry',
    (t) async {
      final api = NoticeApi()..historyGone = true;
      await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('notice-2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Sahifani ochish'));
      await t.pumpAndSettle();
      expect(find.byType(TopupHistoryPage), findsOneWidget);
      expect(
        t.widget<TopupHistoryPage>(find.byType(TopupHistoryPage)).topupId,
        api.targetId,
      );
      expect(
        api.requests,
        contains('GET /wallet/topups/${api.targetId}/history'),
      );
      expect(find.textContaining('Tarix yuklanmadi.'), findsOneWidget);
      expect(find.text('Paynet Xolis'), findsNothing);
      api.historyGone = false;
      await t.tap(find.text('Qayta urinish'));
      await t.pumpAndSettle();
      expect(find.textContaining('Tarix yuklanmadi.'), findsNothing);
    },
  );
  testWidgets('malformed notification target cannot become a route', (t) async {
    final api = NoticeApi()..targetId = '../../admin/users';
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    expect(find.text('Sahifani ochish'), findsNothing);
    expect(api.requests.any((p) => p.contains('/wallet/')), isFalse);
    expect(find.text('TEST reason 2'), findsWidgets);
  });
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
