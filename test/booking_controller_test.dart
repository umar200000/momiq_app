import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';
import 'package:momiq_app/features/bookings/data/booking_controller.dart';
import 'package:momiq_app/features/bookings/presentation/bookings_page.dart';

Map<String, dynamic> copy(Map<String, dynamic> x) => jsonDecode(jsonEncode(x));

class BookingMemory extends WalletDraftStorage {
  Map<String, dynamic>? value;
  bool failWrite = false, failClear = false;
  @override
  Future<Map<String, dynamic>?> read() async =>
      value == null ? null : copy(value!);
  @override
  Future<void> write(Map<String, dynamic> data) async {
    if (failWrite) throw StateError('disk unavailable');
    value = copy(data);
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('clear failed');
    value = null;
  }
}

Map<String, dynamic> fixture() => {
  'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'revision': 0,
  'status': 'pending',
  'myRole': 'sitter',
  'replyDeadline': '2026-10-28T12:00:00Z',
  'snapshot': {
    'sitterName': 'TEST sitter',
    'customerName': 'TEST client',
    'startsAt': '2026-11-01T13:00:00Z',
    'endsAt': '2026-11-02T05:00:00Z',
    'pets': [
      {'name': 'TEST cat', 'notes': 'care'},
    ],
    'address': {'address': 'Toshkent'},
    'instructions': '',
    'price': {
      'billable_days': 1,
      'service_total_minor': 50000000,
      'commission_bps': 1000,
      'commission_minor': 5000000,
    },
  },
  'history': [],
};

class BookingApiFake extends CustomerApi {
  BookingApiFake() : super('token', 'owner');
  Map<String, dynamic> booking = fixture();
  final List<Map<String, dynamic>> posts = [];
  bool loseResponse = false;
  Completer<void>? hold;
  final Set<String> keys = {};
  int charges = 0;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'GET') return copy(booking);
    posts.add({'path': path, 'body': copy(body!)});
    if (hold != null) await hold!.future;
    if (keys.add(body['requestId'])) {
      charges++;
      booking['revision'] = 1;
      booking['status'] = 'accepted';
    }
    if (loseResponse) {
      loseResponse = false;
      throw TimeoutException('response lost');
    }
    return copy(booking);
  }
}

class BookingListApi extends CustomerApi {
  BookingListApi() : super('token', 'owner');
  bool fail = false;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add(path);
    if (fail) throw TimeoutException('offline');
    return {
      'items': [
        {'id': 'a', 'status': path.contains('?') ? 'accepted' : 'pending'},
        if (path.contains('?')) {'id': 'b', 'status': 'pending'},
      ],
      'nextCursor': path.contains('?') ? null : '1',
    };
  }
}

class HandoverApi extends BookingApiFake {
  HandoverApi() {
    booking['status'] = 'accepted';
    booking['revision'] = 1;
    booking['confirmations'] = {
      'start': {'mine': false, 'peer': false},
      'complete': {'mine': false, 'peer': false},
    };
  }
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'GET') return copy(booking);
    posts.add({'path': path, 'body': copy(body!)});
    if (keys.add(body['requestId'])) {
      booking['revision']++;
      booking['confirmations'][path.split('/').last]['mine'] = true;
    }
    if (loseResponse) {
      loseResponse = false;
      throw TimeoutException('lost confirmation response');
    }
    return copy(booking);
  }
}

class DelayedInboxApi extends CustomerApi {
  DelayedInboxApi() : super('test', 'owner');
  final requests = <String>[];
  final replies = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    requests.add(path);
    final reply = Completer<Map<String, dynamic>>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('amendment notice never sends a hidden change or cancellation', (
    t,
  ) async {
    final api = BookingApiFake();
    final c = BookingController(api, fixture()['id'], storage: BookingMemory());
    await t.pumpWidget(
      MaterialApp(
        home: BookingDetailPage(api: api, id: fixture()['id'], controller: c),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('bookingAmendmentPolicy')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Yangi so‘rov eskisini avtomatik bekor qilmaydi.'),
      findsOneWidget,
    );
    await t.tap(find.text('Yopish'));
    await t.pumpAndSettle();
    expect(api.posts, isEmpty);
    expect(c.booking!['revision'], 0);
  });
  test(
    'filter change invalidates pending pagination and cannot lose new loading state',
    () async {
      final api = DelayedInboxApi();
      final c = BookingInboxController(api);
      addTearDown(c.dispose);
      final initial = c.load();
      api.replies[0].complete({
        'items': [
          {'id': 'old', 'status': 'pending'},
        ],
        'nextCursor': '10',
      });
      await initial;
      final oldPage = c.load(more: true);
      final newest = c.filters(bucket: 'history', query: '  МомиҚ &_%  ');
      expect(c.items, isEmpty);
      expect(c.cursor, isNull);
      api.replies[1].complete({
        'items': [
          {'id': 'stale'},
        ],
        'nextCursor': '8',
      });
      await oldPage;
      expect(c.loading, isTrue);
      expect(c.items, isEmpty);
      final request = Uri.parse(api.requests[2]);
      expect(request.queryParameters, {'bucket': 'history', 'q': 'МомиҚ &_%'});
      api.replies[2].complete({
        'items': [
          {'id': 'new', 'status': 'completed'},
        ],
        'nextCursor': '5',
      });
      await newest;
      final more = c.load(more: true);
      expect(Uri.parse(api.requests.last).queryParameters, {
        'bucket': 'history',
        'q': 'МомиҚ &_%',
        'before': '5',
      });
      api.replies[3].complete({'items': [], 'nextCursor': null});
      await more;
      expect(c.items.single['id'], 'new');
      expect(c.loading, isFalse);
    },
  );
  testWidgets(
    'inbox search, bucket and reset use server filtering and show booking context',
    (t) async {
      final api = DelayedInboxApi();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: BookingInbox(api: api)),
          ),
        ),
      );
      api.replies[0].complete({'items': [], 'nextCursor': null});
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('bookingSearch')), 'Momi');
      await t.tap(find.byKey(const ValueKey('bookingBucket-history')));
      await t.pump();
      expect(Uri.parse(api.requests.last).queryParameters, {
        'bucket': 'history',
        'q': 'Momi',
      });
      api.replies.last.complete({
        'items': [
          {
            'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'status': 'completed',
            'peerName': 'TEST sitter',
            'service': 'boarding',
            'startsAt': '2026-11-01T13:00:00Z',
            'serviceTotalMinor': 10000000,
            'pets': [
              {'name': 'Momi', 'type': 'Mushuk'},
            ],
          },
        ],
        'nextCursor': null,
      });
      await t.pumpAndSettle();
      expect(find.textContaining('TEST sitter · Uyda qarash'), findsOneWidget);
      expect(find.textContaining('100000 UZS'), findsOneWidget);
      await t.tap(find.text('Tozalash'));
      await t.pump();
      expect(api.requests.last, '/bookings');
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('bookingSearch')))
            .controller!
            .text,
        '',
      );
      api.replies.last.complete({'items': [], 'nextCursor': null});
      await t.pumpAndSettle();
    },
  );
  test(
    'start confirmation survives restart and retries without a new command',
    () async {
      final api = HandoverApi()..loseResponse = true;
      final memory = BookingMemory();
      final first = BookingController(api, fixture()['id'], storage: memory);
      await first.load();
      expect(await first.act('start'), isFalse);
      first.dispose();
      final next = BookingController(api, fixture()['id'], storage: memory);
      addTearDown(next.dispose);
      await next.load();
      expect(await next.act('start'), isTrue);
      expect(api.posts[0], api.posts[1]);
      expect(api.booking['revision'], 2);
      expect(api.charges, 0);
    },
  );
  testWidgets(
    'handover waits for the peer and completion explains unchanged price',
    (t) async {
      final api = HandoverApi();
      final c = BookingController(
        api,
        fixture()['id'],
        storage: BookingMemory(),
      );
      await t.pumpWidget(
        MaterialApp(
          home: BookingDetailPage(api: api, id: fixture()['id'], controller: c),
        ),
      );
      await t.pumpAndSettle();
      final start = find.byKey(const ValueKey('confirmBooking-start'));
      await t.ensureVisible(start);
      await t.tap(start);
      await t.pumpAndSettle();
      expect(find.textContaining('Ikkala tomon tasdiqlagach'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Tasdiqlash'));
      await t.pumpAndSettle();
      expect(start, findsNothing);
      expect(
        find.textContaining('Ikkinchi tomon tasdig‘i kutilmoqda.'),
        findsOneWidget,
      );
      api.booking['status'] = 'active';
      api.booking['confirmations']['start']['peer'] = true;
      await c.load();
      await t.pumpAndSettle();
      final finish = find.byKey(const ValueKey('confirmBooking-complete'));
      await t.ensureVisible(finish);
      await t.tap(finish);
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'Oldinroq tugatish kelishilgan narxni o‘zgartirmaydi',
        ),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Tasdiqlash'));
      await t.pumpAndSettle();
      expect(finish, findsNothing);
      expect(c.booking!['status'], 'active');
      expect(api.posts.map((p) => (p['body'] as Map)['reason']), ['', '']);
      expect(api.charges, 0);
    },
  );
  test(
    'conversation inbox uses only its participant-scoped endpoint for every page',
    () async {
      final api = BookingListApi();
      final c = BookingInboxController(api, conversationId: 'chat');
      addTearDown(c.dispose);
      await c.load();
      await c.load(more: true);
      expect(api.paths, [
        '/conversations/chat/bookings',
        '/conversations/chat/bookings?before=1',
      ]);
    },
  );
  test(
    'inbox deduplicates pages and retains visible data on offline refresh',
    () async {
      final api = BookingListApi();
      final c = BookingInboxController(api);
      addTearDown(c.dispose);
      await c.load();
      expect(c.cursor, '1');
      await c.load(more: true);
      expect(c.items, hasLength(2));
      expect(c.items.first['status'], 'accepted');
      expect(c.cursor, isNull);
      api.fail = true;
      await c.load();
      expect(c.items, hasLength(2));
      expect(c.error, isNotNull);
      api.fail = false;
      await c.load();
      expect(c.items, hasLength(1));
      expect(c.error, isNull);
    },
  );
  test('lost response and restart retry original action once', () async {
    final api = BookingApiFake()..loseResponse = true;
    final storage = BookingMemory();
    final first = BookingController(api, fixture()['id'], storage: storage);
    await first.load();
    expect(await first.act('accept'), isFalse);
    expect(first.booking!['status'], 'pending');
    expect(storage.value, isNotNull);
    first.dispose();
    final reopened = BookingController(api, fixture()['id'], storage: storage);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.booking!['status'], 'accepted');
    expect(await reopened.act('accept'), isTrue);
    expect(api.posts[0], api.posts[1]);
    expect(api.charges, 1);
    expect(storage.value, isNull);
  });
  test(
    'storage write failure sends nothing and clear failure remains retryable',
    () async {
      final api = BookingApiFake();
      final storage = BookingMemory()..failWrite = true;
      final c = BookingController(api, fixture()['id'], storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.act('accept'), isFalse);
      expect(api.posts, isEmpty);
      storage.failWrite = false;
      storage.failClear = true;
      expect(await c.act('accept'), isFalse);
      expect(c.booking!['status'], 'accepted');
      expect(c.pending, isNotNull);
      storage.failClear = false;
      expect(await c.act('accept'), isTrue);
      expect(api.charges, 1);
    },
  );
  test('double tap and logout cannot apply a late response', () async {
    final api = BookingApiFake()..hold = Completer<void>();
    final c = BookingController(api, fixture()['id'], storage: BookingMemory());
    addTearDown(c.dispose);
    await c.load();
    final sending = c.act('accept');
    await Future<void>.delayed(Duration.zero);
    expect(await c.act('accept'), isFalse);
    expect(api.posts, hasLength(1));
    CustomerApi.sessionVersion++;
    api.hold!.complete();
    expect(await sending, isFalse);
    expect(c.booking!['status'], 'pending');
  });
  test(
    'clearing uncertainty reloads authoritative status without cancelling',
    () async {
      final api = BookingApiFake()..loseResponse = true;
      final c = BookingController(
        api,
        fixture()['id'],
        storage: BookingMemory(),
      );
      addTearDown(c.dispose);
      await c.load();
      await c.act('accept');
      await c.discardUncertainAction();
      expect(c.pending, isNull);
      expect(c.booking!['status'], 'accepted');
      expect(api.posts, hasLength(1));
    },
  );
  testWidgets('sitter sees exact commission before confirming acceptance', (
    t,
  ) async {
    final api = BookingApiFake();
    final c = BookingController(api, fixture()['id'], storage: BookingMemory());
    await t.pumpWidget(
      MaterialApp(
        home: BookingDetailPage(api: api, id: fixture()['id'], controller: c),
      ),
    );
    await t.pumpAndSettle();
    final button = find.byKey(const ValueKey('acceptBooking'));
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('50000 UZS komissiya'), findsOneWidget);
    expect(api.posts, isEmpty);
    await t.tap(find.widgetWithText(FilledButton, 'Tasdiqlash'));
    await t.pumpAndSettle();
    expect(find.text('Qabul qilingan'), findsOneWidget);
    expect(api.charges, 1);
    expect(find.byKey(const ValueKey('acceptBooking')), findsNothing);
  });
}
