import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/auth/presentation/pages/phone_page.dart';
import 'package:momiq_app/features/onboarding/data/profile_photo_source.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/myid_page.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';

class FakePhotos extends ProfilePhotoSource {
  final Uint8List bytes = File('assets/images/myid_pets.png').readAsBytesSync();
  int homeCount = 3;
  bool cancel = false;
  bool fail = false;
  int? requestedLimit;
  ImageSource? profileSource;
  ImageSource? homeSource;
  @override
  Future<Uint8List?> pickProfile({
    ImageSource source = ImageSource.gallery,
  }) async {
    profileSource = source;
    if (fail) throw Exception('Unavailable');
    return cancel ? null : bytes;
  }

  @override
  Future<List<Uint8List>> pickHome(
    int remaining, {
    ImageSource source = ImageSource.gallery,
  }) async {
    homeSource = source;
    requestedLimit = remaining;
    return List.generate(homeCount, (_) => bytes);
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  SharedPreferences.setMockInitialValues({});
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });
  testWidgets(
    'correct OTP briefly stays green then opens manual sitter registration',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OtpPage(phone: '+998 90 123 45 67')),
      );
      await tester.enterText(find.byKey(const ValueKey('otpInput')), '111111');
      await tester.pump();
      expect(find.byKey(const ValueKey('otpBox0')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byType(MyIdPage), findsNothing);
      expect(find.byType(SitterRegistrationPage), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('sitterFirst')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('sitterLast')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isFalse,
      );
      expect(find.text('Sudralib yuruvchilar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final systemBack in [false, true]) {
    testWidgets('registration returns to phone with systemBack=$systemBack', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PhonePage()));
      await tester.enterText(
        find.byKey(const ValueKey('phoneInput')),
        '901234567',
      );
      await tapVisible(tester, find.text('Kod yuborish'));
      await tester.enterText(find.byKey(const ValueKey('otpInput')), '111111');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byType(SitterRegistrationPage), findsOneWidget);
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('Orqaga'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PhonePage), findsOneWidget);
      expect(find.byType(MyIdPage), findsNothing);
      expect(find.byType(OtpPage), findsNothing);
      expect(find.byType(SitterRegistrationPage), findsNothing);
      expect(find.text('90 123 45 67'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('camera choice reaches both photo pickers and years use digits', (
    tester,
  ) async {
    final source = FakePhotos()..homeCount = 1;
    await tester.pumpWidget(
      MaterialApp(home: SitterRegistrationPage(photoSource: source)),
    );
    await tapVisible(tester, find.byKey(const ValueKey('profileUpload')));
    await tapVisible(tester, find.byKey(const ValueKey('photoCamera')));
    expect(source.profileSource, ImageSource.camera);
    await tapVisible(tester, find.byKey(const ValueKey('homeUpload-0')));
    await tapVisible(tester, find.byKey(const ValueKey('photoCamera')));
    expect(source.homeSource, ImageSource.camera);
    expect(find.text('1 / 9 ta rasm'), findsOneWidget);
    final years = find.byKey(const ValueKey('experienceYears'));
    await tester.ensureVisible(years);
    expect(tester.widget<TextField>(years).keyboardType, TextInputType.number);
    await tester.enterText(years, 'a2b');
    expect(find.text('2'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('form viewport meets keyboard without extra system bottom gap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: SitterRegistrationPage(photoSource: FakePhotos())),
    );
    await tester.pumpAndSettle();
    final scroll = find.byType(SingleChildScrollView).first;
    expect(tester.getRect(scroll).bottom, closeTo(500, .1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'registration requires manual name and persists it before opening home',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SitterRegistrationPage(photoSource: FakePhotos())),
      );
      await tapVisible(tester, find.byKey(const ValueKey('registerSubmit')));
      expect(find.byType(SitterHomePage), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('sitterFirst')));
      await tester.enterText(find.byKey(const ValueKey('sitterFirst')), 'Umar');
      await tester.enterText(
        find.byKey(const ValueKey('sitterLast')),
        'Ruziev',
      );
      await tapVisible(tester, find.byKey(const ValueKey('registerSubmit')));
      expect(find.byType(SitterHomePage), findsOneWidget);
      expect(
        tester.widget<SitterHomePage>(find.byType(SitterHomePage)).avatar,
        isNull,
      );
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      final saved = await SharedPreferences.getInstance();
      expect(saved.getString('mock.profile.first'), 'Umar');
      expect(saved.getString('mock.profile.last'), 'Ruziev');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('optional uploaded avatar is passed to home', (tester) async {
    final source = FakePhotos();
    await tester.pumpWidget(
      MaterialApp(home: SitterRegistrationPage(photoSource: source)),
    );
    await tapVisible(tester, find.byKey(const ValueKey('profileUpload')));
    await tapVisible(tester, find.byKey(const ValueKey('photoGallery')));
    await tester.ensureVisible(find.byKey(const ValueKey('sitterFirst')));
    await tester.enterText(find.byKey(const ValueKey('sitterFirst')), 'Umar');
    await tester.enterText(find.byKey(const ValueKey('sitterLast')), 'Ruziev');
    await tapVisible(tester, find.byKey(const ValueKey('registerSubmit')));
    expect(
      tester.widget<SitterHomePage>(find.byType(SitterHomePage)).avatar,
      same(source.bytes),
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('home photo cap is enforced even if picker returns too many', (
    tester,
  ) async {
    final source = FakePhotos()..homeCount = 12;
    await tester.pumpWidget(
      MaterialApp(home: SitterRegistrationPage(photoSource: source)),
    );
    await tapVisible(tester, find.byKey(const ValueKey('homeUpload-0')));
    await tapVisible(tester, find.byKey(const ValueKey('photoGallery')));
    expect(source.requestedLimit, 9);
    expect(find.text('9 / 9 ta rasm'), findsOneWidget);
    expect(find.byKey(const ValueKey('homeUpload-9')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gallery cancellation and failure leave form usable', (
    tester,
  ) async {
    final source = FakePhotos()..cancel = true;
    await tester.pumpWidget(
      MaterialApp(home: SitterRegistrationPage(photoSource: source)),
    );
    await tapVisible(tester, find.byKey(const ValueKey('profileUpload')));
    await tapVisible(tester, find.byKey(const ValueKey('photoGallery')));
    expect(find.byKey(const ValueKey('profileUpload')), findsOneWidget);
    source.fail = true;
    await tapVisible(tester, find.byKey(const ValueKey('profileUpload')));
    await tapVisible(tester, find.byKey(const ValueKey('photoGallery')));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'registration scrolls on small keyboard-open screen without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: SitterRegistrationPage(photoSource: FakePhotos())),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('experienceDetails')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('experienceDetails')),
        'Tipratikan',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
