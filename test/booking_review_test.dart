import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/reviews/presentation/booking_review_page.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'conversation_test.dart' show ChatDraft;

class ReviewApi extends CustomerApi {
  ReviewApi() : super('test', 'customer');
  bool loseResponse = false;
  Completer<void>? gate;
  ReviewJson? review;
  ReviewJson extra = {};
  final posts = <ReviewJson>[], saved = <String>{};
  final receipts = <String, ReviewJson>{};
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
          'id': '12',
          'name': 'TEST author',
          'created': '2026-10-29T00:00:00Z',
          'updated': '2026-10-29T00:00:00Z',
          'stars': body['stars'],
          'text': (body['text'] as String).trim(),
          'revision': (review?['revision'] ?? 0) + 1,
          'withdrawn': body['action'] == 'withdraw',
          'hidden': false,
          'testOnly': true,
        };
      }
      receipts.putIfAbsent(
        body['requestId'],
        () => {
          'requestId': body['requestId'],
          'reviewId': review!['id'],
          'revision': review!['revision'],
          'action': body['action'],
        },
      );
      if (loseResponse) {
        loseResponse = false;
        throw StateError('Lost response');
      }
    } else if (gate != null) {
      await gate!.future;
    }
    return {
      'bookingId': path.split('/')[2],
      'reviewEditable': false,
      if (method == 'POST') 'acknowledgement': receipts[body!['requestId']],
      'review': review,
      'canCreate': review == null,
      'canEdit': false,
      'canWithdraw': review != null && review!['withdrawn'] != true,
      'canRestore': review?['withdrawn'] == true,
      ...extra,
    };
  }
}

void main() {
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('review confirmation and retry fit 320px at 2x in $language', (
      t,
    ) async {
      final previousLanguage = AppLanguage.current.value;
      AppLanguage.current.value = language;
      addTearDown(() => AppLanguage.current.value = previousLanguage);
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = ReviewApi()..loseResponse = true;
      final c = BookingReviewController(api, 'booking', storage: ChatDraft());
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BookingReviewPage(
            api: api,
            bookingId: 'booking',
            controller: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      Future<void> reach(Finder target) async {
        await t.scrollUntilVisible(
          target.hitTestable(),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
      }

      final submit = find.byKey(const ValueKey('submitReview'));
      final star = find.byKey(const ValueKey('reviewStar-4'));
      await reach(star);
      await t.tap(star);
      final input = find.byKey(const ValueKey('reviewText'));
      await reach(input);
      await t.enterText(input, 'TEST original review');
      t.view.viewInsets = const FakeViewPadding(bottom: 240);
      await t.pumpAndSettle();
      await reach(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(api.posts, isEmpty);
      final confirm = find.byKey(const ValueKey('confirmReview'));
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(api.posts.single['stars'], 4);
      expect(c.pending, isNotNull);
      t.view.viewInsets = const FakeViewPadding();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(input).enabled, false);
      await reach(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(api.posts, hasLength(2));
      expect(api.posts.last, api.posts.first);
      expect(api.saved, hasLength(1));
      expect(c.pending, isNull);
      expect(input, findsNothing);
      expect(find.text('TEST original review'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'hidden review shows author decision and server appeal capability',
    (t) async {
      CustomerApi.active = null;
      final api = ReviewApi()
        ..review = {
          'id': '12',
          'name': 'TEST author',
          'withdrawn': false,
          'testOnly': true,
          'created': '2026-10-29T00:00:00Z',
          'updated': '2026-10-29T00:00:00Z',
          'stars': 3,
          'text': 'TEST original',
          'revision': 2,
          'hidden': true,
        }
        ..extra = {
          'moderation': {
            'reason': 'TEST moderation reason',
            'revision': 2,
            'decidedAt': '2026-10-29T00:00:00Z',
          },
          'appealTarget': {
            'kind': 'review',
            'id': '12',
            'purpose': 'appeal',
            'revision': '2',
          },
        };
      final c = BookingReviewController(api, 'booking', storage: ChatDraft());
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingReviewPage(
            api: api,
            bookingId: 'booking',
            controller: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('TEST moderation reason'), findsOneWidget);
      final button = t.widget<PublicContentReportButton>(
        find.byType(PublicContentReportButton),
      );
      expect(button.target, api.extra['appealTarget']);
      expect(api.posts, isEmpty);
      api.extra = {};
      await c.load();
      await t.pumpAndSettle();
      expect(find.byType(PublicContentReportButton), findsNothing);
      expect(find.text('TEST moderation reason'), findsNothing);
    },
  );
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
