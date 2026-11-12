import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_controller.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_data.dart';
import 'booking_dispute_test.dart' show DisputeApi;
import 'conversation_test.dart' show ChatDraft;

Map<String, dynamic> message(int id) => {
  'id': '$id',
  'revision': id,
  'mine': true,
  'role': 'customer',
  'action': 'evidence',
  'text': 'TEST evidence',
  'hasImage': false,
  'created': '2026-10-29T00:00:00Z',
};

class BrokenDisputeApi extends DisputeApi {
  String? broken;
  Map<String, dynamic>? page;
  @override
  Future<DisputeJson> request(
    String method,
    String path, [
    DisputeJson? body,
  ]) async {
    final value = await super.request(method, path, body);
    if (method == 'POST') {
      if (broken == 'request') {
        value['acknowledgement'] = {
          ...value['acknowledgement'],
          'requestId': 'other',
        };
      }
      if (broken == 'revision') {
        value['acknowledgement'] = {...value['acknowledgement'], 'revision': 0};
      }
      if (broken == 'text') {
        value['items'] = [
          {...value['items'][0], 'text': 'Different'},
        ];
      }
      if (broken == 'missing') value.remove('acknowledgement');
    } else {
      if (broken == 'booking') value['bookingId'] = 'another';
      if (broken == 'money') value['customerServicePaymentRefunded'] = true;
      if (broken == 'capability') value['canAddEvidence'] = 'true';
      if (page != null) return {...value, ...page!};
    }
    return value;
  }
}

void main() {
  for (final failure in ['request', 'revision', 'text', 'missing']) {
    test(
      'dispute $failure acknowledgement keeps original evidence and retry identity',
      () async {
        final api = BrokenDisputeApi()..broken = failure, storage = ChatDraft();
        final c = BookingDisputeController(api, 'a' * 32, storage: storage);
        addTearDown(c.dispose);
        await c.load();
        final before = c.data;
        expect(await c.send('Original evidence', null), false);
        expect(c.data, same(before));
        final pending = Map.of(c.pending!);
        expect(storage.value, pending);
        api.broken = null;
        expect(await c.send('Replacement', null), true);
        expect(api.posts, [pending, pending]);
        expect(storage.value, isNull);
        expect(api.messages.length, 1);
      },
    );
  }
  test(
    'dispute invalid owner state never replaces the last valid view',
    () async {
      final api = BrokenDisputeApi();
      final c = BookingDisputeController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(c.dispose);
      await c.load();
      final before = c.data;
      for (final failure in ['booking', 'money', 'capability']) {
        api.broken = failure;
        await c.load();
        expect(c.data, same(before));
        expect(c.error, isNotNull);
      }
    },
  );
  test('dispute history page is atomic and backward bounded', () async {
    final api = BrokenDisputeApi();
    api.messages.addAll([for (var i = 1; i <= 40; i++) message(i)]);
    final initial = await api.request('GET', '/bookings/${'a' * 32}/dispute');
    api.page = {
      ...initial,
      'items': [for (var i = 21; i <= 40; i++) message(i)],
      'nextCursor': '21',
    };
    final c = BookingDisputeController(api, 'a' * 32, storage: ChatDraft());
    addTearDown(c.dispose);
    await c.load();
    expect(c.data!['items'].length, 20);
    final before = c.data;
    api.page = {
      ...initial,
      'items': [
        message(19),
        {...message(20), 'mine': 'true'},
      ],
      'nextCursor': null,
    };
    await c.load(more: true);
    expect(c.data, same(before));
    expect(c.error, isNotNull);
    api.page = {
      ...initial,
      'items': [message(19), message(20)],
      'nextCursor': null,
    };
    await c.load(more: true);
    expect(c.data!['items'].length, 22);
    expect(c.data!['nextCursor'], isNull);
  });
  test('malformed saved dispute remains stored and cannot be posted', () async {
    final api = BrokenDisputeApi(),
        storage = ChatDraft()..value = {'requestId': 'x' * 32, 'text': 'TEST'};
    final c = BookingDisputeController(api, 'a' * 32, storage: storage);
    addTearDown(c.dispose);
    await c.load();
    expect(c.error, isNotNull);
    expect(c.data, isNull);
    expect(await c.send('Replace', null), false);
    expect(api.posts, isEmpty);
    expect(storage.value, isNotNull);
    expect(() => disputeDraft({'text': 'TEST'}), throwsFormatException);
  });
  test(
    'valid original receipt survives later resolution and pagination',
    () async {
      final api = BrokenDisputeApi();
      final c = BookingDisputeController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Original evidence', null), true);
      final request = api.posts.single;
      api.resolved = true;
      final reply = await api.request(
        'POST',
        '/bookings/${'a' * 32}/dispute',
        request,
      );
      reply['items'] = [];
      expect(
        disputeData(reply, 'a' * 32, request: request)['case']['status'],
        'resolved',
      );
    },
  );
}
