import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';
import 'package:momiq_app/features/customer/presentation/customer_reviews.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('sitter details opens all reviews and returns to same profile', (
    t,
  ) async {
    final store = CustomerStore();
    await store.load();
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: SitterDetailPage(store: store, sitter: customerSitters.first),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('viewSitterReviews')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView).first, const Offset(0, -350));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('viewSitterReviews')));
    await t.pumpAndSettle();
    expect(find.byType(CustomerSitterReviewsPage), findsOneWidget);
    expect(find.text('Hoji Sherhojiyiv'), findsOneWidget);
    expect(find.text('Madina Karimova'), findsOneWidget);
    expect(find.text('25.09.2026'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(SitterDetailPage), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test(
    'own completed review belongs only to its sitter and survives reload',
    () async {
      final store = CustomerStore();
      await store.load();
      await store.update(
        (data) => (data['bookings'] as List).add({
          'id': 'review-test',
          'sitter': 'hoji',
          'status': 'completed',
          'to': '2026-10-14',
          'review': {
            'stars': 3,
            'text': 'Mening shaxsiy sharhim',
            'date': '2026-10-14',
          },
        }),
      );
      final reopened = CustomerStore();
      await reopened.load();
      final reviews = customerSitterReviews(reopened, customerSitters.first);
      expect(reviews.length, 5);
      expect(reviews.first['text'], 'Mening shaxsiy sharhim');
      expect(reviews.first['own'], isTrue);
      expect(
        customerSitterReviews(
          reopened,
          customerSitters[1],
        ).where((r) => r['own'] == true),
        isEmpty,
      );
      await reopened.update((data) {
        final booking = (data['bookings'] as List).firstWhere(
          (b) => b['id'] == 'review-test',
        );
        booking['review']['text'] = 'Tahrirlangan sharh';
      });
      expect(
        customerSitterReviews(reopened, customerSitters.first).first['text'],
        'Tahrirlangan sharh',
      );
      expect(customerReviewSummary(reopened, customerSitters.first), '4.4 (5)');
    },
  );
}
