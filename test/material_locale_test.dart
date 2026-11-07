import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/main.dart';

void main() {
  testWidgets(
    'calendar and dialog language follows the persisted app language',
    (tester) async {
      SharedPreferences.setMockInitialValues({'language': 'uz'});
      await AppLanguage.restore();
      addTearDown(() => AppLanguage.current.value = 'uz');
      await tester.pumpWidget(AppLanguage(child: const Momiq()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      String dateForCurrentLocale(String language) {
        final context = tester.element(find.byType(Scaffold).first);
        expect(Localizations.localeOf(context).languageCode, language);
        final labels =
            MaterialLocalizations.of(context) as GlobalMaterialLocalizations;
        return labels.formatMonthYear(DateTime(2026, 10));
      }

      final uzDate = dateForCurrentLocale('uz');
      await AppLanguage.select('ru');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final ruDate = dateForCurrentLocale('ru');
      await AppLanguage.select('en');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final enDate = dateForCurrentLocale('en');
      expect({uzDate, ruDate, enDate}.length, 3);
      expect(
        (await SharedPreferences.getInstance()).getString('language'),
        'en',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
