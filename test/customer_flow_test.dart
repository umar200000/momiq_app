import 'feed_fixture.dart';
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
    final s = CustomerStore(
      feedRepository: const FixtureCustomerFeedRepository(),
      petSession: CustomerPetSession(),
    );
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

  for (final remove in [false, true]) {
    testWidgets(
      'optional customer registration photo persists, remove=$remove',
      (t) async {
        final s = await store();
        await open(
          t,
          CustomerProfileForm(
            store: s,
            registration: true,
            photoSource: PetPhotos(),
          ),
        );
        expect(find.text('Profil rasmi (ixtiyoriy)'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('pickCustomerProfilePhoto')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('profilePhoto-gallery')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('removeCustomerProfilePhoto')),
          findsOneWidget,
        );
        if (remove) {
          await t.tap(find.byKey(const ValueKey('removeCustomerProfilePhoto')));
          await t.pumpAndSettle();
        }
        await t.ensureVisible(find.byKey(const ValueKey('customerFirst')));
        await t.enterText(
          find.byKey(const ValueKey('customerFirst')),
          'Actual',
        );
        await t.enterText(find.byKey(const ValueKey('customerLast')), 'User');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('registerCustomer')));
        await t.pumpAndSettle();
        expect(find.byType(CustomerHomePage), findsOneWidget);
        expect(s.profile['photo'], remove ? isNull : isNotEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
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
  testWidgets('legacy booking route cannot open an offline sample form', (
    t,
  ) async {
    final s = await store();
    await open(t, CustomerBookingForm(store: s, sitter: customerSitters.first));
    expect(
      find.textContaining('Hisobingizga kiring va katalogni yangilang'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('bookingNext')), findsNothing);
    expect(find.textContaining('Oybek'), findsNothing);
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
      final saved = CustomerStore(
        feedRepository: const FixtureCustomerFeedRepository(),
      );
      await saved.load();
      expect(saved.profile['first'], 'Malika');
      expect(saved.profile['last'], 'Aliyeva');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('chat is empty without real conversations', (t) async {
    final s = await store();
    await open(
      t,
      Scaffold(
        body: SingleChildScrollView(child: CustomerChatList(store: s)),
      ),
    );
    expect(find.text('Hali suhbat yo‘q'), findsOneWidget);
    expect(find.text('Hoji Sherhojiyiv'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('operator reply is visibly attributed to Momiq support', (
    t,
  ) async {
    final s = await store();
    addTearDown(s.dispose);
    await s.update(
      (data) => data['messages'] = [
        {
          'id': 'test-support-message',
          'sitter': 'hoji',
          'text': 'TEST operator reply',
          'mine': false,
          'senderRole': 'support',
          'time': '2026-10-28T00:00:00Z',
        },
      ],
    );
    await open(
      t,
      Scaffold(
        body: SingleChildScrollView(child: CustomerChatList(store: s)),
      ),
    );
    expect(
      find.text('Momiq yordam xizmati: TEST operator reply'),
      findsOneWidget,
    );
    await t.tap(find.text('Hoji Sherhojiyiv'));
    await t.pumpAndSettle();
    expect(find.text('Momiq yordam xizmati'), findsOneWidget);
    expect(find.text('TEST operator reply'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('conversation with unavailable sitter does not crash', (t) async {
    final s = await store();
    await s.update(
      (d) => d['messages'] = [
        {
          'sitter': 'deleted-sitter',
          'text': 'History',
          'mine': true,
          'time': 'bad-date',
        },
      ],
    );
    await open(
      t,
      Scaffold(
        body: SingleChildScrollView(child: CustomerChatList(store: s)),
      ),
    );
    expect(find.text('Enaga mavjud emas'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Enaga mavjud emas'));
    await t.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('chat search filters names and displays empty results', (
    t,
  ) async {
    final s = await store();
    await s.update(
      (d) => d['messages'] = [
        {
          'sitter': 'hoji',
          'text': 'Hello',
          'mine': true,
          'time': '2026-01-01T12:00:00Z',
        },
        {
          'sitter': 'nilufar',
          'text': 'Hello',
          'mine': true,
          'time': '2026-01-01T13:00:00Z',
        },
      ],
    );
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
