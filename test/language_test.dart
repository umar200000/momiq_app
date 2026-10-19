import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/role_selection/presentation/pages/role_selection_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.current.value = 'uz';
  });
  tearDown(() => AppLanguage.current.value = 'uz');
  testWidgets(
    'language changes immediately, persists, and follows auth navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppLanguage(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const RoleSelectionPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rolingizni tanlang'), findsOneWidget);
      for (final pair in [
        ('en', 'Choose your role'),
        ('ru', 'Выберите роль'),
        ('uz', 'Rolingizni tanlang'),
      ]) {
        await tester.tap(find.byKey(ValueKey('language-${pair.$1}')));
        await tester.pumpAndSettle();
        expect(find.text(pair.$2), findsOneWidget);
        expect(
          (await SharedPreferences.getInstance()).getString('language'),
          pair.$1,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('language-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Няня'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Продолжить'));
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(find.text('Ваш номер телефона'), findsOneWidget);
      expect(find.text('Отправить код'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      AppLanguage.current.value = 'uz';
      await AppLanguage.restore();
      expect(AppLanguage.current.value, 'ru');
    },
  );
}
