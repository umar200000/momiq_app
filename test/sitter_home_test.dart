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
        // Let Flutter report layout errors with their source locations.
        if (index == 0) {
          for (var animal = 0; animal < 7; animal++) {
            expect(
              find.byKey(ValueKey('request-$animal')),
              animal < 2 ? findsOneWidget : findsNothing,
            );
          }
        }
        if (index == 1) {
          expect(
            find.byKey(const ValueKey('accepted-booking')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('request-0')), findsNothing);
          for (var status = 1; status < 3; status++) {
            await tester.ensureVisible(
              find.byKey(ValueKey('orderStatus-$status')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(ValueKey('orderStatus-$status')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('accepted-booking')),
              findsNothing,
            );
            if (status == 1) {
              for (var animal = 0; animal < 7; animal++) {
                expect(find.byKey(ValueKey('request-$animal')), findsOneWidget);
              }
            } else {
              expect(find.byKey(const ValueKey('request-0')), findsNothing);
              expect(find.text('Luna'), findsOneWidget);
              expect(find.text('Mimi'), findsOneWidget);
            }
          }
          await tester.tap(find.byKey(const ValueKey('homeNav-0')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('homeNav-1')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('accepted-booking')),
            findsOneWidget,
          );
        }
        if (index == 3) {
          expect(find.text('#MQ-0248 · Momi'), findsOneWidget);
          expect(find.text('#MQ-0241 · Boni'), findsOneWidget);
        }
        if (index == 4) expect(find.text('Hoji Sherhojiyiv'), findsNWidgets(2));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
