import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';

const place = CareLocation(
  latitude: 41.3,
  longitude: 69.2,
  address: 'Toshkent, Yunusobod',
);
ServiceListing listing(
  ServiceType type, {
  Set<PetType> pets = const {PetType.cat},
  int capacity = 1,
  CareLocation? location = place,
  int price = 80000,
  bool active = true,
}) => ServiceListing(
  type: type,
  pets: pets,
  capacity: type == ServiceType.boarding ? capacity : null,
  location: location,
  dailyPrice: price,
  active: active,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ListingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ListingStore();
    await store.load();
  });
  tearDown(() => store.dispose());

  test(
    'boarding and personal accept exactly one species; visits accept both',
    () {
      for (final type in [ServiceType.boarding, ServiceType.personal]) {
        expect(
          store.validate(listing(type, pets: {PetType.dog, PetType.cat})),
          ListingProblem.pets,
        );
        expect(store.validate(listing(type, pets: {})), ListingProblem.pets);
      }
      expect(
        store.validate(
          listing(
            ServiceType.homeVisit,
            pets: {PetType.dog, PetType.cat},
            location: null,
          ),
        ),
        isNull,
      );
    },
  );

  test('capacity is one in an apartment and up to three in a house', () async {
    expect(
      store.validate(listing(ServiceType.boarding, capacity: 2)),
      ListingProblem.capacity,
    );
    await store.setHousing(HousingType.house);
    expect(store.validate(listing(ServiceType.boarding, capacity: 3)), isNull);
    expect(
      store.validate(listing(ServiceType.boarding, capacity: 4)),
      ListingProblem.capacity,
    );
    expect(
      store.validate(listing(ServiceType.boarding, capacity: 0)),
      ListingProblem.capacity,
    );
  });

  test('location and positive daily price are mandatory', () {
    for (final type in ServiceType.values) {
      expect(store.validate(listing(type, price: 0)), ListingProblem.price);
      expect(store.validate(listing(type, price: -1)), ListingProblem.price);
      expect(
        store.validate(listing(type, location: null)),
        type == ServiceType.homeVisit ? isNull : ListingProblem.location,
      );
    }
    expect(
      store.validate(
        listing(
          ServiceType.boarding,
          location: const CareLocation(
            latitude: 100,
            longitude: 69,
            address: 'Invalid',
          ),
        ),
      ),
      ListingProblem.location,
    );
  });

  test(
    'personal service conflicts in both directions without silently deactivating',
    () async {
      await store.save(listing(ServiceType.boarding));
      await store.save(listing(ServiceType.homeVisit));
      await expectLater(
        store.save(listing(ServiceType.personal)),
        throwsA(
          isA<ListingException>().having(
            (e) => e.problem,
            'problem',
            ListingProblem.conflict,
          ),
        ),
      );
      expect(store[ServiceType.boarding]!.active, isTrue);
      expect(store[ServiceType.homeVisit]!.active, isTrue);
      await store.setActive(ServiceType.boarding, false);
      await store.setActive(ServiceType.homeVisit, false);
      await store.save(listing(ServiceType.personal));
      await expectLater(
        store.setActive(ServiceType.boarding, true),
        throwsA(isA<ListingException>()),
      );
      await expectLater(
        store.setActive(ServiceType.homeVisit, true),
        throwsA(isA<ListingException>()),
      );
      expect(store[ServiceType.personal]!.active, isTrue);
      await store.setActive(ServiceType.personal, false);
      await store.setActive(ServiceType.boarding, true);
      expect(store[ServiceType.boarding]!.active, isTrue);
    },
  );

  test(
    'edited price, coordinates, active status and housing survive reload',
    () async {
      await store.setHousing(HousingType.house);
      await store.save(listing(ServiceType.boarding, capacity: 3));
      await store.save(
        listing(
          ServiceType.boarding,
          pets: {PetType.dog},
          price: 120000,
          capacity: 2,
          active: false,
        ),
      );
      final restored = ListingStore();
      await restored.load();
      expect(restored.housing, HousingType.house);
      expect(restored[ServiceType.boarding]!.pets, {PetType.dog});
      expect(restored[ServiceType.boarding]!.dailyPrice, 120000);
      expect(restored[ServiceType.boarding]!.capacity, 2);
      expect(restored[ServiceType.boarding]!.location!.latitude, 41.3);
      expect(restored[ServiceType.boarding]!.active, isFalse);
      restored.dispose();
    },
  );

  test(
    'switching to an apartment prevents a live over-capacity listing',
    () async {
      await store.setHousing(HousingType.house);
      await store.save(listing(ServiceType.boarding, capacity: 3));
      await store.setHousing(HousingType.apartment);
      expect(store[ServiceType.boarding]!.capacity, 1);
      expect(store[ServiceType.boarding]!.active, isFalse);
    },
  );

  test('invalid data is not silently overwritten', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ListingStore.storageKey, '{broken');
    final invalidStore = ListingStore();
    await expectLater(invalidStore.load(), throwsFormatException);
    expect(prefs.getString(ListingStore.storageKey), '{broken');
    invalidStore.dispose();
  });
}
