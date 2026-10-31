import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/reviews/presentation/booking_review_page.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_care_page.dart';
import 'package:momiq_app/features/care/presentation/booking_videos_page.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_controller.dart';
import 'package:momiq_app/features/bookings/presentation/booking_dispute_page.dart';
import 'booking_review_test.dart' show ReviewApi;
import 'booking_care_test.dart' show CareApi;
import 'booking_video_test.dart' show VideoApi;
import 'booking_dispute_test.dart' show DisputeApi;
import 'conversation_test.dart' show ChatDraft;

Map<String, dynamic> savedReview(String text) => {
  'id': '12',
  'name': 'TEST author',
  'stars': 4,
  'text': text,
  'revision': 1,
  'hidden': false,
  'withdrawn': false,
  'testOnly': true,
  'created': '2026-10-29T00:00:00Z',
  'updated': '2026-10-29T00:00:00Z',
};

class FlowApi extends CustomerApi {
  FlowApi(this.kind, this.label) : super('TEST', 'customer') {
    delegate = switch (kind) {
      'review' => ReviewApi()..review = savedReview(label),
      'care' => CareApi(),
      'video' => VideoApi(),
      _ =>
        DisputeApi()
          ..messages.add({
            'id': '1',
            'role': 'customer',
            'mine': true,
            'action': 'report',
            'revision': 1,
            'text': label,
            'created': '2026-10-29T00:00:00Z',
            'hasImage': false,
          }),
    };
  }
  final String kind, label;
  late CustomerApi delegate;
  Completer<void>? gate;
  bool fail = false;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add('$method $path');
    if (gate != null) await gate!.future;
    if (fail) throw StateError('TEST failed old source');
    final value = await delegate.request(method, path, body);
    if (kind == 'care') value['originalInstructions'] = label;
    if (kind == 'video') {
      value['pets'] = [
        {'id': 'cat', 'name': label},
      ];
    }
    return value;
  }
}

dynamic controller(String kind, CustomerApi api, String id) => switch (kind) {
  'review' => BookingReviewController(api, id, storage: ChatDraft()),
  'care' => BookingCareController(api, id, storage: ChatDraft()),
  'video' => BookingVideoController(
    api,
    id,
    storage: ChatDraft(),
    explanationStorage: ChatDraft(),
  ),
  _ => BookingDisputeController(api, id, storage: ChatDraft()),
};
Widget page(String kind, CustomerApi api, String id, dynamic c) =>
    switch (kind) {
      'review' => BookingReviewPage(api: api, bookingId: id, controller: c),
      'care' => BookingCarePage(api: api, bookingId: id, controller: c),
      'video' => BookingVideosPage(api: api, bookingId: id, controller: c),
      _ => BookingDisputePage(api: api, id: id, controller: c),
    };

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'immutable review confirmation fits 320px and 2x text in $language',
      (t) async {
        AppLanguage.current.value = language;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final api = ReviewApi();
        final current = controller('review', api, 'a' * 32);
        addTearDown(current.dispose);
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: page('review', api, 'a' * 32, current),
          ),
        );
        await t.pumpAndSettle();
        final star = find.byKey(const ValueKey('reviewStar-4'));
        await t.ensureVisible(star);
        await t.tap(star);
        await t.pump();
        final submit = find.byKey(const ValueKey('submitReview'));
        await t.ensureVisible(submit);
        await t.tap(submit);
        await t.pumpAndSettle();
        final confirm = find.byKey(const ValueKey('confirmReview'));
        await t.ensureVisible(confirm);
        expect(t.widget<FilledButton>(confirm).onPressed, isNotNull);
        expect(t.takeException(), isNull);
        expect(api.posts, isEmpty);
        await t.tap(confirm);
        await t.pumpAndSettle();
        expect(api.posts.length, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'video source picker closes on target replacement before opening native picker',
    (t) async {
      final api = VideoApi();
      final ca = controller('video', api, 'a' * 32),
          cb = controller('video', api, 'b' * 32);
      addTearDown(ca.dispose);
      addTearDown(cb.dispose);
      await t.pumpWidget(MaterialApp(home: page('video', api, 'a' * 32, ca)));
      await t.pumpAndSettle();
      final add = find.byTooltip('Video qo‘shish').first;
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pumpAndSettle();
      expect(find.text('Video yozish'), findsOneWidget);
      await t.pumpWidget(MaterialApp(home: page('video', api, 'b' * 32, cb)));
      await t.pumpAndSettle();
      expect(find.text('Video yozish'), findsNothing);
      expect(ca.pending, isNull);
      expect(cb.pending, isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('dispute confirmation is removed when its booking changes', (
    t,
  ) async {
    final api = DisputeApi();
    final a = controller('dispute', api, 'a' * 32),
        b = controller('dispute', api, 'b' * 32);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(MaterialApp(home: page('dispute', api, 'a' * 32, a)));
    await t.pumpAndSettle();
    final field = find.byKey(const ValueKey('disputeText'));
    await t.ensureVisible(field);
    await t.enterText(field, 'TEST reason');
    final submit = find.byKey(const ValueKey('submitDispute'));
    await t.ensureVisible(submit);
    await t.tap(submit);
    await t.pumpAndSettle();
    expect(find.text('Nizo ochilsinmi?'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: page('dispute', api, 'b' * 32, b)));
    await t.pumpAndSettle();
    expect(find.text('Nizo ochilsinmi?'), findsNothing);
    expect(api.posts, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  for (final kind in ['review', 'care', 'video', 'dispute']) {
    for (final fail in [false, true]) {
      testWidgets(
        '$kind ignores old source ${fail ? 'failure' : 'success'} after rebind',
        (t) async {
          final old = FlowApi(kind, 'Old private data')
            ..gate = Completer<void>()
            ..fail = fail;
          final next = FlowApi(kind, 'New private data');
          final a = controller(kind, old, 'a' * 32),
              b = controller(kind, next, 'b' * 32);
          addTearDown(a.dispose);
          addTearDown(b.dispose);
          await t.pumpWidget(MaterialApp(home: page(kind, old, 'a' * 32, a)));
          await t.pump();
          await t.pumpWidget(MaterialApp(home: page(kind, next, 'b' * 32, b)));
          await t.pumpAndSettle();
          expect(b.data, isNotNull);
          old.gate!.complete();
          await t.pumpAndSettle();
          expect(find.textContaining('Old private data'), findsNothing);
          expect(find.textContaining('New private data'), findsWidgets);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('$kind target-only replacement cannot revive an expired API', (
      t,
    ) async {
      final api = FlowApi(kind, 'Private source');
      final a = controller(kind, api, 'a' * 32);
      addTearDown(a.dispose);
      await t.pumpWidget(MaterialApp(home: page(kind, api, 'a' * 32, a)));
      await t.pumpAndSettle();
      final calls = api.calls.length;
      CustomerApi.sessionVersion++;
      final b = controller(kind, api, 'b' * 32);
      addTearDown(b.dispose);
      await t.pumpWidget(MaterialApp(home: page(kind, api, 'b' * 32, b)));
      await t.pumpAndSettle();
      expect(find.textContaining('Private source'), findsNothing);
      expect(find.textContaining('Buyurtmani qayta oching'), findsOneWidget);
      expect(api.calls.length, calls);
      expect(b.data, isNull);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$kind rejects a controller from a different API or booking', (
      t,
    ) async {
      final api = FlowApi(kind, 'Original'), other = FlowApi(kind, 'Other');
      final a = controller(kind, api, 'a' * 32);
      addTearDown(a.dispose);
      await t.pumpWidget(MaterialApp(home: page(kind, other, 'a' * 32, a)));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(other.calls, isEmpty);
      await t.pumpWidget(MaterialApp(home: page(kind, api, 'b' * 32, a)));
      await t.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.textContaining('Buyurtmani qayta oching'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'review confirmation belongs to old booking and cannot submit after rebind',
    (t) async {
      final a = ReviewApi(), b = ReviewApi();
      final ca = controller('review', a, 'a' * 32),
          cb = controller('review', b, 'b' * 32);
      addTearDown(ca.dispose);
      addTearDown(cb.dispose);
      await t.pumpWidget(MaterialApp(home: page('review', a, 'a' * 32, ca)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('reviewStar-4')));
      await t.pump();
      final submit = find.byKey(const ValueKey('submitReview'));
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirmReview')), findsOneWidget);
      await t.pumpWidget(MaterialApp(home: page('review', b, 'b' * 32, cb)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirmReview')), findsNothing);
      expect(a.posts, isEmpty);
      expect(b.posts, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('care editor closes on rebind without changing new source', (
    t,
  ) async {
    final a = CareApi()..role = 'customer', b = CareApi()..role = 'customer';
    final ca = controller('care', a, 'a' * 32),
        cb = controller('care', b, 'b' * 32);
    addTearDown(ca.dispose);
    addTearDown(cb.dispose);
    await t.pumpWidget(MaterialApp(home: page('care', a, 'a' * 32, ca)));
    await t.pumpAndSettle();
    final edit = find.byKey(const ValueKey('careInstructions-cat'));
    await t.ensureVisible(edit);
    await t.tap(edit);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('careEditorSave')), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: page('care', b, 'b' * 32, cb)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('careEditorSave')), findsNothing);
    expect(a.posts, isEmpty);
    expect(b.posts, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
