import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_controller.dart';
import 'package:momiq_app/features/bookings/presentation/booking_dispute_page.dart';
import 'conversation_test.dart' show ChatDraft;

class DisputeApi extends CustomerApi {
  DisputeApi() : super('test', 'owner');
  bool allowed = true, lost = false, offline = false, resolved = false;
  String stage = 'complaint_available';
  Completer<void>? gate;
  final posts = <DisputeJson>[],
      requests = <String>{},
      messages = <DisputeJson>[];
  final receipts = <String, DisputeJson>{};
  @override
  Future<DisputeJson> request(
    String method,
    String path, [
    DisputeJson? body,
  ]) async {
    if (offline) throw StateError('offline');
    if (method == 'POST') {
      posts.add(Map.of(body!));
      if (requests.add(body['requestId'])) {
        messages.add({
          'id': '${messages.length + 1}',
          'role': 'customer',
          'mine': true,
          'action': body['action'],
          'revision': messages.length + 1,
          'text': body['text'],
          'created': '2026-10-28T10:00:00Z',
          'hasImage': body['image'] != null,
        });
      }
      receipts.putIfAbsent(
        body['requestId'],
        () => {
          'requestId': body['requestId'],
          'messageId': messages.last['id'],
          'revision': messages.last['revision'],
          'action': body['action'],
          'kind': body['kind'],
        },
      );
      if (lost) {
        lost = false;
        throw StateError('Lost response');
      }
    } else if (gate != null) {
      await gate!.future;
    }
    return {
      'bookingId': path.split('/')[2],
      'bookingStatus': messages.isEmpty
          ? 'accepted'
          : resolved
          ? 'cancelled'
          : 'disputed',
      'serverNow': '2026-10-29T00:00:00Z',
      'refundableMinor': 1500000,
      'customerServicePaymentRefunded': false,
      if (method == 'POST') 'acknowledgement': receipts[body!['requestId']],
      'bookingRevision': messages.isEmpty ? 1 : 2,
      'case': messages.isEmpty
          ? null
          : {
              'bookingId': path.split('/')[2],
              'priorStatus': 'accepted',
              'created': '2026-10-28T10:00:00Z',
              'resolvedAt': resolved ? '2026-10-29T00:00:00Z' : null,
              'outcome': resolved ? 'not_started' : null,
              'revision': messages.length,
              'kind': 'no_show',
              'status': resolved ? 'resolved' : 'open',
              'deadline': '2026-10-30T10:00:00Z',
              'overdue': false,
              'refundMinor': resolved ? 1500000 : 0,
              'reason': resolved ? 'TEST verified decision' : null,
            },
      'canReportNoShow': allowed && messages.isEmpty,
      'canReportService': false,
      'canAddEvidence': messages.isNotEmpty && !resolved,
      'stage': stage,
      'items': List.of(messages),
      'nextCursor': null,
    };
  }
}

void main() {
  test(
    'lost dispute report restores original body and produces one case',
    () async {
      final api = DisputeApi()..lost = true, storage = ChatDraft();
      var c = BookingDisputeController(api, 'a' * 32, storage: storage);
      await c.load();
      expect(await c.send('Original private evidence', null), false);
      final original = Map.of(storage.value!);
      c.dispose();
      c = BookingDisputeController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Changed', null), true);
      expect(api.posts, [original, original]);
      expect(api.requests.length, 1);
      expect(c.pending, isNull);
    },
  );
  test(
    'storage failure sends nothing and server capabilities cannot be bypassed',
    () async {
      final api = DisputeApi()..allowed = false, storage = ChatDraft();
      final c = BookingDisputeController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Too early', null), false);
      expect(api.posts, isEmpty);
      api.allowed = true;
      await c.load();
      storage.failWrite = true;
      expect(await c.send('Disk failed', null), false);
      expect(api.posts, isEmpty);
      storage.failWrite = false;
      expect(await c.send('Changed', null), true);
      expect(api.posts.single['text'], 'Disk failed');
    },
  );
  test('session switch discards late dispute response', () async {
    final api = DisputeApi()..gate = Completer<void>();
    final c = BookingDisputeController(api, 'a' * 32, storage: ChatDraft());
    addTearDown(c.dispose);
    final loading = c.load();
    await Future<void>.delayed(Duration.zero);
    CustomerApi.sessionVersion++;
    api.gate!.complete();
    await loading;
    expect(c.data, isNull);
    expect(c.live, false);
    expect(await c.send('late', null), false);
  });
  testWidgets(
    '15-minute reminder has no dispute action until server permits it',
    (t) async {
      final api = DisputeApi()
        ..allowed = false
        ..stage = 'contact_reminder';
      final c = BookingDisputeController(api, 'a' * 32, storage: ChatDraft());
      await t.pumpWidget(
        MaterialApp(
          home: BookingDisputePage(api: api, id: 'a' * 32, controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('15 daqiqa o‘tdi'), findsOneWidget);
      expect(find.byKey(const ValueKey('submitDispute')), findsNothing);
      api.allowed = true;
      api.stage = 'complaint_available';
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('submitDispute')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'opening a dispute requires explicit confirmation and cancellation sends nothing',
    (t) async {
      final api = DisputeApi(),
          c = BookingDisputeController(
            DisputeApi(),
            'a' * 32,
            storage: ChatDraft(),
          );
      await t.pumpWidget(
        MaterialApp(
          home: BookingDisputePage(api: c.api, id: 'a' * 32, controller: c),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('disputeText')),
        'TEST explanation',
      );
      final send = find.byKey(const ValueKey('submitDispute'));
      await t.scrollUntilVisible(
        send,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(send);
      await t.pumpAndSettle();
      expect(
        find.textContaining('Buyurtmani boshlash/yakunlash admin qarorigacha'),
        findsOneWidget,
      );
      await t.tap(find.text('Ortga'));
      await t.pumpAndSettle();
      expect((c.api as DisputeApi).posts, isEmpty);
      expect(api.posts, isEmpty);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'resolved case is read-only and never describes service money as refunded',
    (t) async {
      final api = DisputeApi()..resolved = true;
      api.messages.add({
        'id': '1',
        'role': 'admin',
        'mine': false,
        'action': 'resolve',
        'revision': 1,
        'text': 'TEST verified decision',
        'created': '2026-10-28T10:00:00Z',
        'hasImage': false,
      });
      final c = BookingDisputeController(api, 'a' * 32, storage: ChatDraft());
      await t.pumpWidget(
        MaterialApp(
          home: BookingDisputePage(api: api, id: 'a' * 32, controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Qaror chiqarilgan'), findsOneWidget);
      expect(find.byKey(const ValueKey('submitDispute')), findsNothing);
      expect(
        find.textContaining(
          'Momiq mijozning enagaga bergan xizmat pulini qaytarmaydi',
        ),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
