import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/profile/presentation/mock_profile_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.current.value = 'uz';
  });
  tearDown(() => AppLanguage.current.value = 'uz');
  Future<void> open(WidgetTester tester, int section) async {
    await tester.pumpWidget(
      AppLanguage(
        child: MaterialApp(
          home: MockProfilePage(
            section: section,
            firstName: 'Hoji',
            lastName: 'Sherhojiyiv',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('saveProfileSection'));
    await tester.scrollUntilVisible(
      button,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('profile edits persist', (tester) async {
    await open(tester, 0);
    await tester.enterText(find.byKey(const ValueKey('profileFirst')), 'Umar');
    await tester.enterText(
      find.byKey(const ValueKey('profileAbout')),
      'It va mushuklarni parvarish qilaman.',
    );
    await save(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mock.profile.first'), 'Umar');
    expect(
      prefs.getString('mock.profile.about'),
      'It va mushuklarni parvarish qilaman.',
    );
  });
  testWidgets('language changes immediately and persists', (tester) async {
    await open(tester, 5);
    await tester.tap(find.byKey(const ValueKey('language-ru')));
    await tester.pumpAndSettle();
    expect(find.text('Язык'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('language'), 'ru');
  });
  testWidgets('notification toggle persists', (tester) async {
    await open(tester, 3);
    await tester.tap(find.byKey(const ValueKey('notifyOrders')));
    await save(tester);
    expect(
      (await SharedPreferences.getInstance()).getBool('mock.notify.orders'),
      isFalse,
    );
  });
  testWidgets('schedule toggle persists', (tester) async {
    await open(tester, 1);
    await tester.tap(find.byKey(const ValueKey('workDay-0')));
    await save(tester);
    expect(
      (await SharedPreferences.getInstance())
          .getStringList('mock.profile.days')!
          .first,
      'false',
    );
  });
  testWidgets('help saves only a mock request', (tester) async {
    await open(tester, 4);
    await tester.enterText(
      find.byKey(const ValueKey('supportMessage')),
      'Sinov murojaati',
    );
    await save(tester);
    expect(
      (await SharedPreferences.getInstance()).getString('mock.support.message'),
      'Sinov murojaati',
    );
    expect(
      find.text('Mock murojaat saqlandi. Haqiqiy xabar yuborilmadi.'),
      findsOneWidget,
    );
  });
}
