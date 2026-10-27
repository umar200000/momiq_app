import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';

class ReviewedCatalog implements CustomerFeedRepository {
  @override
  Future<List<CJson>> fetchSitters({CustomerCoordinates? location}) async => [
    {
      'id': 'abc:boarding',
      'name': 'Test E.',
      'service': 0,
      'pets': ['Mushuk'],
      'price': 100000,
      'capacity': 3,
      'photo': null,
      'homePhotos': [],
      'years': 1,
      'rating': 0,
      'reviews': 0,
      'about': 'TEST',
      'testOnly': true,
      'identityVerified': false,
      'availabilityKnown': false,
    },
  ];
}

void main() {
  testWidgets(
    'reviewed catalog without GPS does not crash or invent availability',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerStore(feedRepository: ReviewedCatalog());
      addTearDown(store.dispose);
      await store.load();
      await store.refreshSitters();
      await tester.pumpWidget(
        MaterialApp(home: CustomerSearchPage(store: store)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Test E.'), findsOneWidget);
      expect(find.text('Masofa aniqlanmagan'), findsOneWidget);
      expect(find.text('Mavjud sanalar hali tasdiqlanmagan'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: SitterDetailPage(store: store, sitter: store.sitters.single),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('bookSitter')))
            .onPressed,
        isNull,
      );
      expect(find.text('Buyurtma berish hali ochilmagan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
