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
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
