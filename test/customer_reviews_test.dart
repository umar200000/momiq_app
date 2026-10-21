import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_reviews.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('no invented review or rating when no reviews exist', (
    tester,
  ) async {
    final store = CustomerStore();
    await store.load();
    addTearDown(store.dispose);
    final sitter = <String, dynamic>{'id': 'actual', 'name': 'Account'};
    expect(customerSitterReviews(store, sitter), isEmpty);
    expect(customerReviewSummary(store, sitter), 'Hali sharh yo‘q');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerReviewsSection(store: store, sitter: sitter),
        ),
      ),
    );
    expect(find.text('Hali sharh yo‘q'), findsOneWidget);
    expect(find.text('Madina Karimova'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
