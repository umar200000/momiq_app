import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('five preview tabs fit compact screen in $language', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppLanguage.current.value = language;
      addTearDown(() => AppLanguage.current.value = 'uz');
      await tester.pumpWidget(
        AppLanguage(
          child: MaterialApp(
            home: SitterHomePage(
              avatar: File('assets/images/myid_pets.png').readAsBytesSync(),
            ),
          ),
        ),
      );
      for (var index = 0; index < 5; index++) {
        await tester.tap(find.byKey(ValueKey('homeNav-$index')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
        expect(find.byKey(const ValueKey('accepted-booking')), findsNothing);
        expect(find.byKey(const ValueKey('request-0')), findsNothing);
        expect(find.text('Hoji Sherhojiyiv'), findsNothing);
        expect(find.text('#MQ-0248 · Momi'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
