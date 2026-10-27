import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'feed_fixture.dart';

void main() {
  for (final notes in [null, '', '   ', 'Ovqatdan keyin dori']) {
    testWidgets(
      'API pet with optional notes=$notes renders and can be edited',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = CustomerStore(
          feedRepository: const FixtureCustomerFeedRepository(),
          petSession: CustomerPetSession(),
        );
        addTearDown(store.dispose);
        await store.load();
        await store.saveItem('pets', {
          'id': 'minimal-api-pet',
          'type': 'Mushuk',
          'photo': base64Encode(
            File('assets/images/service_cat.png').readAsBytesSync(),
          ),
          'notes': ?notes,
        });
        await tester.pumpWidget(
          MaterialApp(home: CustomerPetsPage(store: store)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('null'), findsNothing);
        if (notes == 'Ovqatdan keyin dori') {
          expect(find.text(notes!), findsOneWidget);
        }
        await tester.tap(find.text('Tahrirlash'));
        await tester.pumpAndSettle();
        expect(find.byType(CustomerPetForm), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
