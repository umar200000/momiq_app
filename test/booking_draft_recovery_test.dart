import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_controller.dart';
import 'booking_review_test.dart' show ReviewApi;
import 'booking_care_test.dart' show CareApi, reportValues;
import 'booking_dispute_test.dart' show DisputeApi;
import 'booking_source_test.dart' show page;
import 'conversation_test.dart' show ChatDraft;

dynamic apiFor(String kind) => switch (kind) {
  'review' => ReviewApi(),
  'care' => CareApi(),
  _ => DisputeApi(),
};
dynamic controllerFor(String kind, dynamic api, ChatDraft store) =>
    switch (kind) {
      'review' => BookingReviewController(api, 'a' * 32, storage: store),
      'care' => BookingCareController(api, 'a' * 32, storage: store),
      _ => BookingDisputeController(api, 'a' * 32, storage: store),
    };
Future<bool> send(String kind, dynamic c) async => switch (kind) {
  'review' => await c.submit(4, 'TEST recovered'),
  'care' => await c.save(reportValues()),
  _ => await c.send('TEST recovered', null),
};

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final kind in ['review', 'care', 'dispute']) {
    test(
      '$kind recovery preserves unreadable draft until explicit successful clear',
      () async {
        final api = apiFor(kind), store = ChatDraft()..value = {'broken': true};
        final c = controllerFor(kind, api, store);
        addTearDown(c.dispose);
        await c.load();
        expect(c.invalidDraft, true);
        expect(c.pending, isNull);
        expect(await send(kind, c), false);
        expect(api.posts, isEmpty);
        expect(store.value, {'broken': true});
        store.failClear = true;
        await c.discard();
        expect(c.invalidDraft, true);
        expect(c.error, isA<StateError>());
        expect(store.value, {'broken': true});
        expect(c.busy, false);
        store.failClear = false;
        await c.discard();
        expect(c.invalidDraft, false);
        expect(c.error, isNull);
        expect(c.data, isNotNull);
        expect(store.value, isNull);
        expect(await send(kind, c), true);
        expect(api.posts.length, 1);
      },
    );
    for (final language in ['uz', 'en', 'ru']) {
      testWidgets(
        '$kind unreadable draft recovery is reachable at 320px and 2x in $language',
        (t) async {
          AppLanguage.current.value = language;
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final api = apiFor(kind),
              store = ChatDraft()..value = {'broken': true};
          final c = controllerFor(kind, api, store);
          addTearDown(c.dispose);
          await t.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: page(kind, api, 'a' * 32, c),
            ),
          );
          await t.pumpAndSettle();
          expect(c.invalidDraft, true);
          expect(api.posts, isEmpty);
          final clear = find.byKey(const ValueKey('clearInvalidBookingDraft'));
          await t.scrollUntilVisible(
            clear,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          await t.tap(clear);
          await t.pumpAndSettle();
          if (kind == 'care') {
            final confirm = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(FilledButton),
            );
            await t.ensureVisible(confirm);
            await t.tap(confirm);
            await t.pumpAndSettle();
          }
          expect(c.invalidDraft, false);
          expect(c.data, isNotNull);
          expect(store.value, isNull);
          expect(api.posts, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
