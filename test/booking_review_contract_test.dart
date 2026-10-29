import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/reviews/data/booking_review_data.dart';
import 'booking_review_test.dart' show ReviewApi;
import 'conversation_test.dart' show ChatDraft;

class BrokenReviewApi extends ReviewApi {
  String? breakGet, breakPost;
  @override
  Future<ReviewJson> request(
    String method,
    String path, [
    ReviewJson? body,
  ]) async {
    final value = await super.request(method, path, body);
    switch (method == 'GET' ? breakGet : breakPost) {
      case 'booking':
        value['bookingId'] = 'another';
      case 'capability':
        value['canCreate'] = 'true';
      case 'receipt':
        value['acknowledgement'] = {
          ...value['acknowledgement'],
          'requestId': 'different',
        };
      case 'missingReceipt':
        value.remove('acknowledgement');
      case 'content':
        value['review'] = {...value['review'], 'text': 'Different text'};
      case 'revision':
        value['acknowledgement'] = {...value['acknowledgement'], 'revision': 0};
    }
    return value;
  }
}

void main() {
  for (final failure in ['receipt', 'missingReceipt', 'content', 'revision']) {
    test(
      'unconfirmed $failure never clears the immutable review retry',
      () async {
        final api = BrokenReviewApi()..breakPost = failure, store = ChatDraft();
        final c = BookingReviewController(api, 'booking', storage: store);
        addTearDown(c.dispose);
        await c.load();
        final before = c.data;
        expect(await c.submit(4, '  Original text  '), false);
        expect(identical(c.data, before), true);
        expect(c.pending, isNotNull);
        expect(store.value, isNotNull);
        final pending = Map.of(c.pending!);
        api.breakPost = null;
        // Real server normalizes text; this fixture follows it before retry.
        api.review!['text'] = 'Original text';
        expect(await c.submit(1, 'Replacement'), true);
        expect(api.posts, [pending, pending]);
        expect(store.value, isNull);
      },
    );
  }
  test(
    'wrong booking or malformed capability preserves previous view',
    () async {
      final api = BrokenReviewApi();
      final current = BookingReviewController(
        api,
        'booking',
        storage: ChatDraft(),
      );
      addTearDown(current.dispose);
      await current.load();
      final before = current.data;
      for (final failure in ['booking', 'capability']) {
        api.breakGet = failure;
        await current.load();
        expect(identical(current.data, before), true);
        expect(current.error, isNotNull);
      }
    },
  );
  test('invalid stored review is retained and never submitted', () async {
    final api = ReviewApi(),
        store = ChatDraft()..value = {'requestId': 'invalid', 'stars': 9};
    final c = BookingReviewController(api, 'booking', storage: store);
    addTearDown(c.dispose);
    await c.load();
    expect(c.error, isNotNull);
    expect(c.data, isNull);
    expect(await c.submit(4, 'replacement'), false);
    expect(api.posts, isEmpty);
    expect(store.value, isNotNull);
  });
  test(
    'request receipt remains valid when a newer visibility decision exists',
    () async {
      final api = ReviewApi();
      final current = BookingReviewController(
        api,
        'booking',
        storage: ChatDraft(),
      );
      addTearDown(current.dispose);
      await current.load();
      expect(await current.submit(5, 'Original'), true);
      final request = api.posts.single;
      api.review = {...api.review!, 'revision': 3, 'withdrawn': true};
      final retry = await api.request(
        'POST',
        '/bookings/booking/review',
        request,
      );
      expect(
        bookingReviewData(
          retry,
          'booking',
          request: request,
        )['review']['withdrawn'],
        true,
      );
      retry['acknowledgement'] = {
        ...retry['acknowledgement'],
        'reviewId': '99',
      };
      expect(
        () => bookingReviewData(retry, 'booking', request: request),
        throwsFormatException,
      );
    },
  );
}
