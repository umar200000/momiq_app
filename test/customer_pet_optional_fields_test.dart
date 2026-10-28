import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'feed_fixture.dart';
import 'package:momiq_app/features/customer/presentation/pet_safety.dart';

void main() {
  testWidgets(
    'care form validates contact and keeps all safety fields after save and reopen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: CustomerPetSession(),
      );
      addTearDown(store.dispose);
      await store.load();
      await store.saveItem('pets', {
        'id': 'safety',
        'type': 'Mushuk',
        'name': 'TEST pet',
        'photo': base64Encode(
          File('assets/images/service_cat.png').readAsBytesSync(),
        ),
      });
      await tester.pumpWidget(
        MaterialApp(home: CustomerPetsPage(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tahrirlash'));
      await tester.pumpAndSettle();
      final values = {
        'vaccinations': 'TEST passport',
        'allergies': 'TEST allergy',
        'medications': 'TEST instruction',
        'behavior': 'TEST timid',
        'emergencyName': 'TEST contact',
        'emergencyPhone': '+998900000099',
      };
      for (final e in values.entries) {
        final field = find.byKey(ValueKey('petSafety-${e.key}'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(
          field,
          e.key == 'emergencyPhone' ? 'bad number' : e.value,
        );
      }
      await tester.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerPetForm), findsOneWidget);
      expect(find.text('+ va davlat kodi bilan kiriting.'), findsOneWidget);
      final phone = find.byKey(const ValueKey('petSafety-emergencyPhone'));
      await tester.ensureVisible(phone);
      await tester.enterText(phone, values['emergencyPhone']!);
      await tester.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerPetForm), findsNothing);
      await tester.tap(find.text('Tahrirlash'));
      await tester.pumpAndSettle();
      for (final e in values.entries) {
        final field = tester.widget<TextFormField>(
          find.byKey(ValueKey('petSafety-${e.key}')),
        );
        expect(field.controller!.text, e.value);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'care summary never invents missing facts and renders supplied instructions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PetSafetySummary(
              pet: {
                'allergies': 'TEST allergy',
                'medications': 'TEST instruction',
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('TEST allergy'), findsOneWidget);
      expect(find.textContaining('TEST instruction'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('petSafetySummary-emergencyPhone')),
        findsNothing,
      );
      expect(find.textContaining('noma’lum'), findsOneWidget);
    },
  );
  test(
    'care validation bounds unknown fields and does not infer medical status',
    () {
      for (final field in petSafetyFields) {
        expect(validatePetSafety(field, null), isNull);
        expect(
          validatePetSafety(field, 'x' * (petSafetyLimit(field) + 1)),
          isNotNull,
        );
        expect(validatePetSafety(field, 'x\u0000'), isNotNull);
      }
      expect(validatePetSafety('emergencyPhone', '+998900000099'), isNull);
      expect(validatePetSafety('emergencyPhone', '+998 90'), isNotNull);
    },
  );
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
