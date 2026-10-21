import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:momiq_app/features/splash/presentation/pages/splash_page.dart';
import 'package:momiq_app/features/role_selection/presentation/pages/role_selection_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
  });
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('splash changes at three seconds and replaces its route', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byType(RoleSelectionPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RoleSelectionPage), findsOneWidget);
    expect(find.byType(SplashPage), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(RoleSelectionPage))).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposing splash cancels pending navigation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const MaterialApp(home: Text('Other page')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Other page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact screen supports both roles and continue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: RoleSelectionPage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Mijozman'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('Davom etish'));
    final button = find.byKey(const ValueKey('continueButton'));
    final scaleFinder = find.descendant(
      of: button,
      matching: find.byType(AnimatedScale),
    );
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<AnimatedScale>(scaleFinder).scale, .94);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Orqaga'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Mijozman'));
    await tester.tap(find.text('Mijozman'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(find.text('Davom etish'));
    await tester.tap(find.text('Davom etish'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
