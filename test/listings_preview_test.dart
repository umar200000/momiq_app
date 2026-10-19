import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/core/theme/app_colors.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';
import 'package:momiq_app/features/listings/presentation/service_form_page.dart';

void main() {
  testWidgets('service design previews', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ListingStore.instance;
    await store.load();
    await store.setHousing(HousingType.house);
    await store.save(
      ServiceListing(
        type: ServiceType.boarding,
        pets: {PetType.cat},
        dailyPrice: 80000,
        capacity: 2,
        location: const CareLocation(
          latitude: 41.3,
          longitude: 69.2,
          address: 'Toshkent, Yunusobod',
        ),
      ),
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final weight in [400, 600]) {
      await (FontLoader(
        'Quicksand',
      )..addFont(rootBundle.load('assets/fonts/Quicksand-$weight.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'MomiqBrand',
    )..addFont(rootBundle.load('assets/fonts/Baloo2-700.ttf'))).load();
    final boundaryKey = GlobalKey();
    Widget app(Widget child) => AppLanguage(
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: 'Quicksand',
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.gold),
        ),
        home: RepaintBoundary(key: boundaryKey, child: child),
      ),
    );
    Future<void> capture(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(app(const SitterHomePage()));
    await tester.tap(find.byKey(const ValueKey('homeNav-2')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/service_cat.png'),
        boundaryKey.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
    await capture('listings-preview');
    await tester.pumpWidget(
      app(ServiceFormPage(type: ServiceType.boarding, store: store)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/service_dog.png'),
        boundaryKey.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
    await capture('boarding-form-preview');
    await tester.ensureVisible(find.byKey(const ValueKey('saveListing')));
    await tester.pumpAndSettle();
    await capture('boarding-form-bottom-preview');
    await tester.pumpWidget(app(const SitterRegistrationPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('housing-house')));
    await tester.pumpAndSettle();
    await capture('housing-preview');
    expect(tester.takeException(), isNull);
  });
}
