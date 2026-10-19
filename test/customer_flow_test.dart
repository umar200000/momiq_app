import 'support/pet_fixtures.dart';
import 'package:momiq_app/features/customer/presentation/customer_registration_page.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/myid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_page.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';
import 'package:momiq_app/features/customer/presentation/customer_booking_form.dart';
import 'package:momiq_app/features/customer/presentation/customer_bookings.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:momiq_app/features/auth/presentation/pages/phone_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.current.value = 'uz';
  });
  tearDown(() => AppLanguage.current.value = 'uz');
  Future<CustomerStore> store() async {
    final s = CustomerStore(petSession: CustomerPetSession());
    await s.load();
    await seedTestPets(s);
    return s;
  }

  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      AppLanguage(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
  }

  test(
    'booking totals, persistence, cancellation and pet compatibility',
    () async {
      final s = await store();
      final from = calendarDate(DateTime.now());
      final to = from.add(const Duration(days: 2));
      final id = await s.book(
        sitterId: 'hoji',
        petId: 'momi',
        from: from,
        to: to,
        instructions: {
          'meals': ['08:00'],
          'food': 'Ovqat',
          'medicine': false,
          'walk': false,
        },
        address: {'address': 'Toshkent'},
      );
      expect(careDays(from, to), 3);
      final reopened = CustomerStore();
      await reopened.load();
      final b = reopened.list('bookings').firstWhere((b) => b['id'] == id);
      expect(b['status'], 'pending');
      expect(b['price'] * careDays(from, to), 240000);
      await reopened.cancel(id, 'Reja o‘zgardi');
      expect(reopened.list('bookings').first['status'], 'cancelled');
      await expectLater(
        s.book(
          sitterId: 'hoji',
          petId: 'boni',
          from: from,
          to: to,
          instructions: {
            'meals': ['08:00'],
            'food': 'Ovqat',
            'medicine': false,
          },
          address: {'address': 'Toshkent'},
        ),
        throwsArgumentError,
      );
    },
  );
  test('favorites and chat survive reload', () async {
    final s = await store();
    await s.favorite('hoji');
    await s.send('hoji', 'Salom');
    final next = CustomerStore();
    await next.load();
    expect(next.favorites, ['hoji']);
    expect(next.list('messages').last['text'], 'Salom');
    await next.favorite('hoji');
    expect(next.favorites, isEmpty);
  });
  testWidgets('all four client tabs fit compact screen', (t) async {
    final s = await store();
    await open(t, CustomerHomePage(store: s));
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byKey(ValueKey('customerNav-$i')));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('sitter search returns empty and matching results', (t) async {
    final s = await store();
    await open(t, CustomerSearchPage(store: s));
    await t.enterText(
      find.byKey(const ValueKey('customerSearch')),
      'no sitter',
    );
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Hech narsa topilmadi'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('customerSearch')), 'Hoji');
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Hoji Sherhojiyiv'), findsOneWidget);
    expect(find.text('Nilufar Karimova'), findsNothing);
  });
  testWidgets('pet form creates another animal', (t) async {
    final s = await store();
    await open(t, CustomerPetForm(store: s, photoSource: PetPhotos()));
    await t.tap(find.byKey(const ValueKey('pickCustomerPetPhoto')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('petPhoto-gallery')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Mushuk'));
    await t.enterText(find.byKey(const ValueKey('customerPetName')), 'Luna');
    await t.enterText(find.byKey(const ValueKey('customerPetAge')), '1');
    await t.tap(find.byKey(const ValueKey('saveCustomerPet')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(s.list('pets').last['name'], 'Luna');
  });
  testWidgets('chat send works locally', (t) async {
    final s = await store();
    await open(t, CustomerChatPage(store: s, sitter: customerSitters.first));
    await t.enterText(
      find.byKey(const ValueKey('customerChatInput')),
      'Rahmat',
    );
    await t.tap(find.byKey(const ValueKey('customerChatSend')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(s.list('messages').last['text'], 'Rahmat');
    expect(find.text('Rahmat'), findsOneWidget);
  });
  testWidgets('booking prevents skipping pet selection', (t) async {
    final s = await store();
    await open(t, CustomerBookingForm(store: s, sitter: customerSitters.first));
    await t.tap(find.byKey(const ValueKey('bookingNext')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Hayvonni tanlang.'), findsOneWidget);
    expect(find.text('Boni'), findsNothing);
  });
  testWidgets(
    'customer OTP opens manual registration then saves names before home',
    (t) async {
      await open(t, const OtpPage(phone: '+998 90 123 45 67', customer: true));
      final field = find.byType(TextField).first;
      await t.enterText(field, '111111');
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byType(CustomerHomePage), findsNothing);
      expect(find.byType(MyIdPage), findsNothing);
      expect(find.byType(CustomerRegistrationPage), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('registerCustomer')));
      await t.pumpAndSettle();
      expect(find.byType(CustomerHomePage), findsNothing);
      await t.enterText(find.byKey(const ValueKey('customerFirst')), 'Malika');
      await t.enterText(find.byKey(const ValueKey('customerLast')), 'Aliyeva');
      await t.tap(find.byKey(const ValueKey('registerCustomer')));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byType(CustomerHomePage), findsOneWidget);
      expect(find.byType(MyIdPage), findsNothing);
      final saved = CustomerStore();
      await saved.load();
      expect(saved.profile['first'], 'Malika');
      expect(saved.profile['last'], 'Aliyeva');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('client detail and secondary screens render', (t) async {
    final s = await store();
    for (final page in <Widget>[
      SitterDetailPage(store: s, sitter: customerSitters.first),
      CustomerPetsPage(store: s),
      CustomerProfileForm(store: s),
      CustomerAddressesPage(store: s),
      CustomerSettingsPage(store: s),
      CustomerHelpPage(store: s),
      CustomerBookingDetail(store: s, id: 'MQ-DEMO-01'),
      CustomerCareReport(booking: s.list('bookings').first),
      CustomerReviewPage(store: s, booking: s.list('bookings').last),
    ]) {
      await t.pumpWidget(const SizedBox());
      await open(t, page);
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('complete client booking through four steps', (t) async {
    final s = await store();
    await open(t, CustomerBookingForm(store: s, sitter: customerSitters.first));
    await t.tap(find.text('Momi'));
    await t.tap(find.byKey(const ValueKey('bookingNext')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pickBookingDates')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    final now = DateTime.now();
    await t.tap(find.text('${now.day}').hitTestable().first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.text('${now.day}').hitTestable().first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('bookingNext')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Ovqatlantirish'), findsNothing);
    expect(find.text('Hayvon pasporti'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bookingNext')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('bookingNext')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.byType(CustomerBookingSuccess), findsOneWidget);
    expect(s.list('bookings').first['status'], 'pending');
    expect(s.list('bookings').first['pet']['name'], 'Momi');
  });
  test(
    'three pets multiply total, preserve individual care and require visit coordinates',
    () async {
      final s = await store();
      addTearDown(s.dispose);
      final cat = s.list('pets').first;
      for (final id in ['luna', 'mila']) {
        await s.saveItem('pets', {...cat, 'id': id, 'name': id});
      }
      final care = <String, CJson>{
        for (final id in ['momi', 'luna', 'mila'])
          id: {
            'meals': ['08:00'],
            'food': 'Ovqat $id',
            'medicine': false,
            'walk': false,
          },
      };
      final from = calendarDate(DateTime.now());
      final id = await s.book(
        sitterId: 'hoji',
        petIds: ['momi', 'luna', 'mila'],
        from: from,
        to: from.add(const Duration(days: 1)),
        instructions: care['momi']!,
        petInstructions: care,
        address: {'address': 'Toshkent'},
      );
      final b = s.list('bookings').firstWhere((b) => b['id'] == id);
      expect(bookingPets(b), hasLength(3));
      expect(bookingTotal(b), 480000);
      expect(bookingPetCare(b, bookingPets(b)[1])['food'], 'Ovqat luna');
      final reopened = CustomerStore(petSession: CustomerPetSession());
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(bookingTotal(reopened.list('bookings').first), 480000);
      expect(reopened.list('pets'), isEmpty);
      await expectLater(
        s.book(
          sitterId: 'nilufar',
          petId: 'momi',
          from: from,
          to: from,
          instructions: care['momi']!,
          address: {'address': 'Toshkent'},
        ),
        throwsArgumentError,
      );
      final visit = await s.book(
        sitterId: 'nilufar',
        petId: 'momi',
        from: from,
        to: from,
        instructions: care['momi']!,
        address: {'address': 'Uyim', 'lat': 41.3, 'lon': 69.2},
      );
      expect(
        s
            .list('bookings')
            .firstWhere((b) => b['id'] == visit)['address']['lat'],
        41.3,
      );
    },
  );

  testWidgets(
    'three cats have optional individual passports and triple price',
    (t) async {
      final s = await store();
      final cat = s.list('pets').first;
      for (final name in ['Luna', 'Mila']) {
        await s.saveItem('pets', {...cat, 'id': name, 'name': name});
      }
      await open(
        t,
        CustomerBookingForm(
          store: s,
          sitter: customerSitters.first,
          photoSource: PetPhotos(),
        ),
      );
      for (final name in ['Momi', 'Luna', 'Mila']) {
        await t.ensureVisible(find.text(name));
        await t.tap(find.text(name));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('bookingNext')));
      await t.pumpAndSettle();
      expect(find.text('Ortga'), findsNothing);
      expect(find.textContaining('Enaga manzili:'), findsNothing);
      await t.tap(find.byKey(const ValueKey('pickBookingDates')));
      await t.pumpAndSettle();
      final day = '${DateTime.now().day}';
      await t.tap(find.text(day).hitTestable().first);
      await t.pumpAndSettle();
      await t.tap(find.text(day).hitTestable().first);
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bookingNext')));
      await t.pumpAndSettle();
      for (final entry in [('momi', 'camera'), ('Luna', 'gallery')]) {
        final button = find.byKey(ValueKey('passport-${entry.$1}'));
        await t.ensureVisible(button);
        await t.tap(button);
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('passport-${entry.$2}')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('bookingNext')));
      await t.pumpAndSettle();
      expect(find.textContaining('Enaga har kuni 2 ta video'), findsOneWidget);
      expect(find.text('Jami 240 000 so‘m'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bookingNext')));
      await t.pumpAndSettle();
      expect(find.byType(CustomerBookingSuccess), findsOneWidget);
      final b = s.list('bookings').first;
      expect(bookingPets(b), hasLength(3));
      expect(b['petPassports'].keys, containsAll(['momi', 'Luna']));
      expect(b['petPassports'].containsKey('Mila'), isFalse);
      expect(bookingPetCare(b, bookingPets(b)[2]), isEmpty);
      final reopened = CustomerStore(petSession: CustomerPetSession());
      await reopened.load();
      expect(
        reopened.list('bookings').first['petPassports'],
        b['petPassports'],
      );
      await t.pumpWidget(const SizedBox());
      await open(t, CustomerBookingDetail(store: reopened, id: b['id']));
      expect(find.text('Momi · Hayvon pasporti'), findsOneWidget);
      expect(find.text('Parvarish ko‘rsatmalari'), findsNothing);
      expect(t.takeException(), isNull);
      await open(t, CustomerCareReport(booking: b));
      expect(t.takeException(), isNull);

      expect(t.takeException(), isNull);
    },
  );
  testWidgets('chat search filters names and displays empty results', (
    t,
  ) async {
    final s = await store();
    await open(
      t,
      Scaffold(
        body: SingleChildScrollView(child: CustomerChatList(store: s)),
      ),
    );
    final search = find.byKey(const ValueKey('customerChatSearch'));
    await t.enterText(search, 'Nilufar');
    await t.pumpAndSettle();
    expect(find.text('Nilufar Karimova'), findsOneWidget);
    expect(find.text('Hoji Sherhojiyiv'), findsNothing);
    await t.enterText(search, 'unknown person');
    await t.pumpAndSettle();
    expect(find.text('Suhbat topilmadi'), findsOneWidget);
    await t.enterText(search, '');
    await t.pumpAndSettle();
    expect(find.text('Hoji Sherhojiyiv'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
