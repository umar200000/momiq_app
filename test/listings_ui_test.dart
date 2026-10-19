import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';
import 'package:momiq_app/features/listings/presentation/listings_panel.dart';
import 'package:momiq_app/features/listings/presentation/service_form_page.dart';

const pickedPlace = CareLocation(
  latitude: 41.3,
  longitude: 69.2,
  address: 'Toshkent, Yunusobod',
);
Future<void> tapVisible(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late ListingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ListingStore();
    await store.load();
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    store.dispose();
    AppLanguage.current.value = 'uz';
  });

  Future<void> showPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppLanguage(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListingsPanel(
                store: store,
                locationPicker: (_, current) async => pickedPlace,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'create returns to expanded card; editing pre-fills and persists changes',
    (tester) async {
      await store.setHousing(HousingType.house);
      await showPanel(tester);
      await tapVisible(tester, 'create-boarding');
      expect(find.byKey(const ValueKey('saveListing')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('saveListing')))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, 'pet-dog');
      await tapVisible(tester, 'pet-cat');
      await tapVisible(tester, 'capacity-3');
      await tapVisible(tester, 'chooseCareLocation');
      await tester.enterText(find.byKey(const ValueKey('dailyPrice')), '80000');
      await tester.pumpAndSettle();
      await tapVisible(tester, 'saveListing');
      expect(find.byType(ServiceFormPage), findsNothing);
      expect(store[ServiceType.boarding]!.pets, {PetType.cat});
      expect(store[ServiceType.boarding]!.capacity, 3);
      expect(find.text('80 000 so‘m / kun'), findsOneWidget);
      await tapVisible(tester, 'edit-boarding');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dailyPrice')))
            .controller!
            .text,
        '80 000',
      );
      expect(find.text(pickedPlace.address), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('dailyPrice')), '95000');
      await tapVisible(tester, 'saveListing');
      expect(store[ServiceType.boarding]!.dailyPrice, 95000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('apartment shows only one capacity and needs a map selection', (
    tester,
  ) async {
    await showPanel(tester);
    await tapVisible(tester, 'create-boarding');
    expect(find.byKey(const ValueKey('capacity-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('capacity-2')), findsNothing);
    expect(find.byKey(const ValueKey('capacity-3')), findsNothing);
    await tapVisible(tester, 'pet-cat');
    await tester.enterText(find.byKey(const ValueKey('dailyPrice')), '80000');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('saveListing')))
          .onPressed,
      isNull,
    );
    await tapVisible(tester, 'chooseCareLocation');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('saveListing')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'home visit can select both and does not ask capacity or location',
    (tester) async {
      await showPanel(tester);
      await tapVisible(tester, 'create-homeVisit');
      expect(find.byKey(const ValueKey('capacity-1')), findsNothing);
      expect(find.byKey(const ValueKey('chooseCareLocation')), findsNothing);
      await tapVisible(tester, 'pet-dog');
      await tapVisible(tester, 'pet-cat');
      await tester.enterText(
        find.byKey(const ValueKey('dailyPrice')),
        '100000',
      );
      await tapVisible(tester, 'saveListing');
      expect(store[ServiceType.homeVisit]!.pets, {PetType.dog, PetType.cat});
    },
  );

  testWidgets(
    'personal service waits for explicit deactivation; toggle cannot bypass rule',
    (tester) async {
      await store.save(
        ServiceListing(
          type: ServiceType.homeVisit,
          pets: {PetType.dog},
          dailyPrice: 50000,
        ),
      );
      await showPanel(tester);
      await tapVisible(tester, 'create-personal');
      await tapVisible(tester, 'pet-dog');
      await tapVisible(tester, 'chooseCareLocation');
      await tester.enterText(
        find.byKey(const ValueKey('dailyPrice')),
        '150000',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('saveListing')))
            .onPressed,
        isNull,
      );
      expect(store[ServiceType.homeVisit]!.active, isTrue);
      await tapVisible(tester, 'conflict-homeVisit');
      await tapVisible(tester, 'saveListing');
      expect(store[ServiceType.personal]!.active, isTrue);
      expect(store[ServiceType.homeVisit]!.active, isFalse);
      await tapVisible(tester, 'active-homeVisit');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(store[ServiceType.homeVisit]!.active, isFalse);
      await tapVisible(tester, 'conflict-personal');
      await tester.tap(find.text('Faollashtirish'));
      await tester.pumpAndSettle();
      expect(store[ServiceType.homeVisit]!.active, isTrue);
      expect(store[ServiceType.personal]!.active, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('all service forms fit a compact screen in $language', (
      tester,
    ) async {
      AppLanguage.current.value = language;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final type in ServiceType.values) {
        await tester.pumpWidget(
          AppLanguage(
            child: MaterialApp(
              home: ServiceFormPage(
                key: ValueKey(type),
                type: type,
                store: store,
                locationPicker: (_, current) async => pickedPlace,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, 'pet-dog');
        await tester.ensureVisible(find.byKey(const ValueKey('saveListing')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
