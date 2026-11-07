import 'feed_fixture.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:momiq_app/features/bookings/presentation/booking_request_page.dart';
import 'package:momiq_app/features/bookings/data/booking_composer.dart';
import 'booking_composer_test.dart' show ComposerApi;
import 'booking_controller_test.dart' show BookingMemory;
import 'support/pet_fixtures.dart';

class BookingPetApi extends ComposerApi {
  BookingPetApi(this.pets);
  final List<CJson> pets;
  @override
  Future<CJson> request(String method, String path, [CJson? body]) async {
    final result = await super.request(method, path, body);
    if (path == '/me') result['account']['pets'] = pets;
    return result;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'session starts empty, survives store recreation, never restores from disk',
    () async {
      final session = CustomerPetSession();
      final a = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: session,
      );
      await a.load();
      expect(a.list('pets'), isEmpty);
      await seedTestPets(a);
      await a.favorite('hoji');
      final b = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: session,
      );
      await b.load();
      expect(b.list('pets').length, 2);
      await b.saveItem('pets', {...b.list('pets').first, 'name': 'Yangi ism'});
      expect(a.list('pets').first['name'], 'Yangi ism');
      final fresh = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: CustomerPetSession(),
      );
      await fresh.load();
      expect(fresh.list('pets'), isEmpty);
      expect(fresh.favorites, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(CustomerStore.storageKey)!)['pets'],
        isEmpty,
      );
    },
  );
  test(
    'service types follow boarding, visiting and personal listing rules',
    () {
      expect(
        allowedCustomerPetTypes({
          'service': 1,
          'pets': ['It'],
        }),
        ['It'],
      );
      expect(
        allowedCustomerPetTypes({
          'service': 0,
          'pets': ['It'],
        }),
        ['It'],
      );
      expect(
        allowedCustomerPetTypes({
          'service': 2,
          'pets': ['Mushuk'],
        }),
        ['Mushuk'],
      );
      for (final service in [0, 1, 2]) {
        expect(
          allowedCustomerPetTypes({
            'service': service,
            'pets': ['Boshqa', 'It', 'Mushuk', 'It'],
          }),
          ['It', 'Mushuk'],
        );
      }
    },
  );
  testWidgets(
    'single type is selected; photo required; optional fields may stay empty; edit preserves id',
    (t) async {
      final s = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: CustomerPetSession(),
      );
      await s.load();
      final photos = PetPhotos();
      Future<void> open({Map<String, dynamic>? pet}) async {
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          MaterialApp(
            home: CustomerPetForm(
              store: s,
              pet: pet,
              allowedTypes: const ['It'],
              photoSource: photos,
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await open();
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'It')).selected,
        isTrue,
      );
      expect(find.widgetWithText(ChoiceChip, 'Mushuk'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Boshqa'), findsNothing);
      await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await t.pumpAndSettle();
      expect(s.list('pets'), isEmpty);
      await t.tap(find.byKey(const ValueKey('pickCustomerPetPhoto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('petPhoto-camera')));
      await t.pumpAndSettle();
      expect(photos.source, ImageSource.camera);
      await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await t.pumpAndSettle();
      expect(s.list('pets').single['name'], '');
      final id = s.list('pets').single['id'];
      await open(pet: s.list('pets').single);
      await t.enterText(find.byKey(const ValueKey('customerPetName')), 'Boni');
      await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await t.pumpAndSettle();
      expect(s.list('pets').single['id'], id);
      expect(s.list('pets').single['name'], 'Boni');
    },
  );
  testWidgets(
    'other type requests species and gallery cancellation does not create a pet',
    (t) async {
      final s = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: CustomerPetSession(),
      );
      await s.load();
      final photos = PetPhotos()..cancel = true;
      await t.pumpWidget(
        MaterialApp(
          home: CustomerPetForm(store: s, photoSource: photos),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Boshqa'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('customerPetOtherType')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('pickCustomerPetPhoto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('petPhoto-gallery')));
      await t.pumpAndSettle();
      expect(photos.source, ImageSource.gallery);
      await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await t.pumpAndSettle();
      expect(s.list('pets'), isEmpty);
      photos.cancel = false;
      await t.tap(find.byKey(const ValueKey('pickCustomerPetPhoto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('petPhoto-gallery')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await t.pumpAndSettle();
      expect(s.list('pets'), isEmpty);
      await t.enterText(
        find.byKey(const ValueKey('customerPetOtherType')),
        'Quyon',
      );
      await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
      await t.pumpAndSettle();
      expect(s.list('pets').single['otherType'], 'Quyon');
    },
  );
  testWidgets(
    'booking add form receives listing type and existing pets have edit controls',
    (t) async {
      final s = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
        petSession: CustomerPetSession(),
      );
      await s.load();
      await seedTestPets(s);
      final api = BookingPetApi(s.list('pets'));
      s.api =
          api; // Booking composer and account use the same authenticated source.
      await s.refreshRemote();
      await t.pumpWidget(
        MaterialApp(
          home: BookingRequestPage(
            store: s,
            sitter: customerSitters.first,
            composer: BookingComposer(
              api,
              customerSitters.first['id'],
              storage: BookingMemory(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Momi'), findsOneWidget);
      expect(find.text('Boni'), findsNothing);
      await t.tap(find.byKey(const ValueKey('editBookingPet-momi')));
      await t.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Mushuk'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'It'), findsNothing);
    },
  );
}
