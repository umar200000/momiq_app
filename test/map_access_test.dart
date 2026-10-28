import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';
import 'package:momiq_app/features/listings/presentation/service_form_page.dart';

void main() {
  testWidgets(
    'manual address selection never waits for GPS or a permission prompt',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = ListingStore();
      await store.load();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ServiceFormPage(
            type: ServiceType.boarding,
            store: store,
            locationPicker: (_, current) async {
              opened++;
              return const CareLocation(
                latitude: 41.31,
                longitude: 69.28,
                address: 'TEST manual address',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('chooseCareLocation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chooseCareLocation')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('TEST manual address'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
