import 'package:momiq_app/core/widgets/pressable_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:momiq_app/features/auth/presentation/pages/phone_page.dart';
import 'package:momiq_app/features/role_selection/presentation/pages/role_selection_page.dart';

Widget app(Widget home) => MaterialApp(
  home: home,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
);
Future<void> click(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test('phone formats pasted prefix and keeps cursor edits usable', () {
    final f = UzbekistanPhoneFormatter();
    final value = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '+998901234567',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    expect(value.text, '90 123 45 67');
    expect(value.selection.extentOffset, 12);
    final deleted = f.formatEditUpdate(
      const TextEditingValue(
        text: '90 1',
        selection: TextSelection.collapsed(offset: 3),
      ),
      const TextEditingValue(
        text: '901',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(deleted.text, '91');
  });
  testWidgets('both roles continue to phone and back returns to roles', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app(const RoleSelectionPage()));
    await click(tester, 'Davom etish');
    expect(find.byType(PhonePage), findsOneWidget);
    expect(tester.widget<PhonePage>(find.byType(PhonePage)).customer, isTrue);
    await tester.tap(find.byTooltip('Orqaga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await click(tester, 'Enagaman');
    await click(tester, 'Davom etish');
    expect(find.byType(PhonePage), findsOneWidget);
    expect(tester.widget<PhonePage>(find.byType(PhonePage)).customer, isFalse);
    await tester.tap(find.byTooltip('Orqaga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RoleSelectionPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'phone requires nine digits and opens OTP with formatted number',
    (tester) async {
      await tester.pumpWidget(app(const PhonePage()));
      await click(tester, 'Kod yuborish');
      expect(find.text('9 xonali telefon raqamini kiriting'), findsNothing);
      final phoneBorder = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byKey(const ValueKey('phoneInput')),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((c) => c.decoration is BoxDecoration);
      expect(
        ((phoneBorder.decoration as BoxDecoration).border as Border).top.color,
        Colors.red.shade700,
      );
      await tester.enterText(
        find.byKey(const ValueKey('phoneInput')),
        '+998901234567',
      );
      expect(find.text('90 123 45 67'), findsOneWidget);
      await click(tester, 'Kod yuborish');
      expect(find.byType(OtpPage), findsOneWidget);
      expect(find.textContaining('+998 ** *** ** 67 raqamiga'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'OTP validates, waits twenty seconds and restarts resend countdown',
    (tester) async {
      await tester.pumpWidget(app(const OtpPage(phone: '+998 90 123 45 67')));
      expect(find.text('Qayta jo‘natish · 00:20'), findsOneWidget);
      expect(
        tester
            .widget<PressableButton>(find.byKey(const ValueKey('resendCode')))
            .onPressed,
        isNull,
      );
      await tester.pump();
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('otpInput')),
      );
      expect(input.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.text('Tasdiqlash'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('otpInput')), '22222');
      await tester.pump();
      expect(find.text('Kod noto‘g‘ri. Qayta urinib ko‘ring.'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('otpInput')), '222222');
      await tester.pump();
      expect(find.text('Kod noto‘g‘ri. Qayta urinib ko‘ring.'), findsNothing);
      for (var i = 0; i < 6; i++) {
        final box = tester.widget<Container>(find.byKey(ValueKey('otpBox$i')));
        expect(
          ((box.decoration as BoxDecoration).border as Border).top.color,
          Colors.red.shade700,
        );
      }
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Kodni qayta jo‘natish'), findsOneWidget);
      await tester.ensureVisible(find.text('Kodni qayta jo‘natish'));
      await tester.tap(find.text('Kodni qayta jo‘natish'));
      await tester.pump();
      expect(find.text('Qayta jo‘natish · 00:20'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('otpInput')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byKey(const ValueKey('otpInput')), '111111');
      await tester.pump();
      expect(find.byKey(const ValueKey('otpBox0')), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        final box = tester.widget<Container>(find.byKey(ValueKey('otpBox$i')));
        expect(
          ((box.decoration as BoxDecoration).border as Border).top.color,
          const Color(0xFF4F8059),
        );
      }
      expect(find.byKey(const ValueKey('resendCode')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('otpInput')))
            .readOnly,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 25));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('phone and OTP fit small screen with keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const PhonePage()));
    await tester.enterText(
      find.byKey(const ValueKey('phoneInput')),
      '901234567',
    );
    await click(tester, 'Kod yuborish');
    await tester.enterText(find.byKey(const ValueKey('otpInput')), '111111');
    await tester.pump();
    expect(find.byKey(const ValueKey('otpBox0')), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      final box = tester.widget<Container>(find.byKey(ValueKey('otpBox$i')));
      expect(
        ((box.decoration as BoxDecoration).border as Border).top.color,
        const Color(0xFF4F8059),
      );
    }
    expect(find.byKey(const ValueKey('resendCode')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('auth background stays at screen bottom as keyboard toggles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final page in [
      const PhonePage(),
      const OtpPage(phone: '+998 90 123 45 67'),
    ]) {
      await tester.pumpWidget(app(page));
      await tester.pump();
      final decoration = find.byKey(const ValueKey('authBottomDecoration'));
      final before = tester.getRect(decoration);
      final headerBefore = tester.getRect(
        find.byKey(const ValueKey('authHeader')),
      );
      expect(before.bottom, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(decoration), before);
      expect(
        tester.getRect(find.byKey(const ValueKey('authHeader'))),
        headerBefore,
      );
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(decoration), before);
      expect(
        tester.getRect(find.byKey(const ValueKey('authHeader'))),
        headerBefore,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('tapping header dismisses keyboard on both auth screens', (
    tester,
  ) async {
    for (final page in [
      const PhonePage(),
      const OtpPage(phone: '+998 90 123 45 67'),
    ]) {
      await tester.pumpWidget(app(page));
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.text('Momiq'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
