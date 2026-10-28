import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/reviews/presentation/booking_review_page.dart';
import 'conversation_test.dart' show ChatDraft;

class ReviewApi extends CustomerApi {
  ReviewApi() : super('test', 'customer');
  bool loseResponse = false;
  Completer<void>? gate;
  ReviewJson? review;
  final posts = <ReviewJson>[], saved = <String>{};
  @override
  Future<ReviewJson> request(
    String method,
    String path, [
    ReviewJson? body,
  ]) async {
    if (method == 'POST') {
      posts.add(Map.of(body!));
      if (saved.add(body['requestId'])) {
        review = {
          'stars': body['stars'],
          'text': body['text'],
          'revision': (review?['revision'] ?? 0) + 1,
          'withdrawn': body['action'] == 'withdraw',
          'hidden': false,
          'testOnly': true,
        };
      }
      if (loseResponse) {
        loseResponse = false;
        throw StateError('Lost response');
      }
    } else if (gate != null) {
      await gate!.future;
    }
    return {
      'review': review,
      'canCreate': review == null,
      'canEdit': false,
      'canWithdraw': review != null && review!['withdrawn'] != true,
      'canRestore': review?['withdrawn'] == true,
    };
  }
}

void main() {
  test(
    'lost response survives restart with original immutable payload',
    () async {
      final api = ReviewApi()..loseResponse = true, storage = ChatDraft();
      var c = BookingReviewController(api, 'booking', storage: storage);
      await c.load();
      expect(await c.submit(2, 'Original'), false);
      final first = Map.of(storage.value!);
      c.dispose();
      c = BookingReviewController(api, 'booking', storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.submit(5, 'Replacement'), true);
      expect(api.posts, [first, first]);
      expect(api.saved.length, 1);
      expect(c.data!['review']['stars'], 2);
      expect(storage.value, isNull);
    },
  );
  test(
    'persistence failure blocks POST and session switch discards late GET',
    () async {
      final api = ReviewApi(), storage = ChatDraft()..failWrite = true;
      final c = BookingReviewController(api, 'booking', storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.submit(3, 'Saved first'), false);
      expect(api.posts, isEmpty);
      final late = BookingReviewController(
        api,
        'booking',
        storage: ChatDraft(),
      );
      addTearDown(late.dispose);
      api.gate = Completer<void>();
      final loading = late.load();
      await Future<void>.delayed(Duration.zero);
      CustomerApi.sessionVersion++;
      api.gate!.complete();
      await loading;
      expect(late.data, isNull);
      expect(late.live, false);
    },
  );
  test('clear failure retains exact request for safe retry', () async {
    final api = ReviewApi(), storage = ChatDraft()..failClear = true;
    final c = BookingReviewController(api, 'booking', storage: storage);
    addTearDown(c.dispose);
    await c.load();
    expect(await c.submit(4, 'Review'), false);
    expect(c.pending, isNotNull);
    storage.failClear = false;
    expect(await c.submit(1, 'Must not replace'), true);
    expect(api.posts.first, api.posts.last);
    expect(api.saved.length, 1);
  });
  testWidgets(
    'rating requires choice and confirmation; saved content has no editor',
    (t) async {
      final api = ReviewApi();
      final controller = BookingReviewController(
        api,
        'booking',
        storage: ChatDraft(),
      );
      addTearDown(controller.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingReviewPage(
            api: api,
            bookingId: 'booking',
            controller: controller,
          ),
        ),
      );
      await t.pumpAndSettle();
      final submit = find.byKey(const ValueKey('submitReview'));
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('reviewStar-2')));
      await t.enterText(
        find.byKey(const ValueKey('reviewText')),
        'Original text',
      );
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(api.posts, isEmpty);
      await t.tap(find.byKey(const ValueKey('confirmReview')));
      await t.pumpAndSettle();
      expect(api.posts.single['stars'], 2);
      expect(find.byKey(const ValueKey('reviewText')), findsNothing);
      expect(find.text('Original text'), findsOneWidget);
      await t.tap(find.text('Sharhni yashirish'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('confirmReview')));
      await t.pumpAndSettle();
      expect(api.posts.last['action'], 'withdraw');
      expect(api.posts.last['text'], 'Original text');
      expect(find.text('Ayni sharhni tiklash'), findsOneWidget);
    },
  );
  testWidgets('lost submission locks editor and retry cannot change rating', (
    t,
  ) async {
    final api = ReviewApi()..loseResponse = true;
    final c = BookingReviewController(api, 'booking', storage: ChatDraft());
    addTearDown(c.dispose);
    await c.load();
    await c.submit(1, 'Original');
    await t.pumpWidget(
      MaterialApp(
        home: BookingReviewPage(api: api, bookingId: 'booking', controller: c),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byKey(const ValueKey('reviewText'))).enabled,
      false,
    );
    expect(
      t
          .widget<IconButton>(find.byKey(const ValueKey('reviewStar-5')))
          .onPressed,
      isNull,
    );
    final retry = find.byKey(const ValueKey('submitReview'));
    await t.ensureVisible(retry);
    await t.tap(retry);
    await t.pumpAndSettle();
    expect(api.posts.first, api.posts.last);
    expect(api.saved.length, 1);
    expect(find.byKey(const ValueKey('confirmReview')), findsNothing);
  });
}
