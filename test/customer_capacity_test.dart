import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_booking_form.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';
import 'support/pet_fixtures.dart';

void main() {
  late CustomerStore store;
  final care = <String, dynamic>{
    'meals': ['08:00'],
    'food': 'Ovqat',
    'medicine': false,
    'walk': false,
  };
  final address = <String, dynamic>{
    'lat': 41.3,
    'lon': 69.2,
    'address': 'Uyim',
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = CustomerStore(petSession: CustomerPetSession());
    await store.load();
    await seedTestPets(store);
    final dog = store.list('pets').last;
    await store.saveItem('pets', {...dog, 'id': 'dog2', 'name': 'Rex'});
  });
  tearDown(() => store.dispose());
  test('mock free, partial, full and personal capacities', () {
    expect(store.availablePlaces(customerSitter('hoji')), 3);
    expect(store.availablePlaces(customerSitter('nilufar')), 3);
    expect(store.availablePlaces(customerSitter('sitora')), 0);
    expect(store.availablePlaces(customerSitter('aziz')), 1);
    expect(sitterCapacity({'service': 0, 'capacity': 7}), 3);
    expect(sitterCapacity({'service': 1, 'capacity': 2}), 3);
    expect(sitterCapacity({'service': 2, 'capacity': 3}), 1);
  });
  test(
    'personal rejects two pets and fully booked sitter rejects one',
    () async {
      final today = calendarDate(DateTime.now());
      for (final sitter in ['aziz', 'sitora']) {
        await expectLater(
          store.book(
            sitterId: sitter,
            petIds: sitter == 'aziz' ? ['boni', 'dog2'] : ['boni'],
            from: today,
            to: today,
            instructions: care,
            address: address,
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'one visiting booking blocks all other clients until cancelled',
    () async {
      final today = calendarDate(DateTime.now());
      final id = await store.book(
        sitterId: 'nilufar',
        petIds: ['momi'],
        from: today,
        to: today,
        instructions: care,
        address: address,
      );
      expect(store.availablePlaces(customerSitter('nilufar')), 0);
      await expectLater(
        store.book(
          sitterId: 'nilufar',
          petId: 'dog2',
          from: today,
          to: today,
          instructions: care,
          address: address,
        ),
        throwsStateError,
      );
      expect(
        store.availablePlaces(
          customerSitter('nilufar'),
          from: today.add(const Duration(days: 1)),
        ),
        3,
      );
      await store.cancel(id, 'Sinov');
      expect(store.availablePlaces(customerSitter('nilufar')), 3);
    },
  );
  test(
    'non-overlapping bookings use peak occupancy, not summed occupancy',
    () async {
      final today = calendarDate(DateTime.now());
      for (final offset in [0, 2]) {
        final day = today.add(Duration(days: offset));
        await store.book(
          sitterId: 'nilufar',
          petId: 'momi',
          from: day,
          to: day,
          instructions: care,
          address: address,
        );
      }
      expect(
        store.availablePlaces(
          customerSitter('nilufar'),
          from: today,
          to: today.add(const Duration(days: 2)),
        ),
        0,
      );
    },
  );
  test('free visiting sitter accepts three pets in one request', () async {
    final today = calendarDate(DateTime.now());
    await store.book(
      sitterId: 'nilufar',
      petIds: ['momi', 'boni', 'dog2'],
      from: today,
      to: today,
      address: address,
    );
    expect(store.availablePlaces(customerSitter('nilufar')), 0);
    expect(store.availablePlaces(customerSitter('malika')), 0);
  });
  testWidgets('visiting cards show status without pet capacity', (t) async {
    for (final id in ['nilufar', 'malika']) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SitterCard(store: store, sitter: customerSitter(id)),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(id == 'nilufar' ? 'Bo‘sh' : 'Band'), findsOneWidget);
      expect(find.textContaining('ta joy'), findsNothing);
      expect(find.textContaining('ta band'), findsNothing);
    }
  });
  test(
    'busy visitor becomes bookable on first free date, not before',
    () async {
      final sitter = customerSitter('malika');
      final first = store.firstAvailableDate(sitter);
      final today = calendarDate(DateTime.now());
      expect(first.isAfter(today), isTrue);
      expect(store.availablePlaces(sitter, from: first), 3);
      expect(
        store.availablePlaces(
          sitter,
          from: first.subtract(const Duration(days: 1)),
        ),
        0,
      );
      await expectLater(
        store.book(
          sitterId: 'malika',
          petId: 'momi',
          from: today,
          to: first,
          address: address,
        ),
        throwsStateError,
      );
      final end = first.add(const Duration(days: 2));
      await store.book(
        sitterId: 'malika',
        petId: 'momi',
        from: first,
        to: end,
        address: address,
      );
      expect(
        store.firstAvailableDate(sitter),
        end.add(const Duration(days: 1)),
      );
    },
  );
  testWidgets('personal selection keeps one pet and shows capacity', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: CustomerBookingForm(store: store, sitter: customerSitter('aziz')),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Boni'));
    await t.tap(find.text('Boni'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Rex'));
    await t.tap(find.text('Rex'));
    await t.pumpAndSettle();
    expect(
      find.text('Ko‘pi bilan 1 ta hayvon tanlash mumkin.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(find.text('Tanlandi: 1 / 1 ta'), findsOneWidget);
  });
  testWidgets('full sitter detail opens booking from first free day', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: SitterDetailPage(store: store, sitter: customerSitter('sitora')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('To‘liq band · bo‘sh joy yo‘q'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bookSitter')));
    await t.pumpAndSettle();
    expect(find.byType(CustomerBookingForm), findsOneWidget);
    expect(
      find.text(
        'Buyurtma boshlanishi: ${shortDate(store.firstAvailableDate(customerSitter('sitora')).toIso8601String())}',
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
