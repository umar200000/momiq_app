import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/profile/presentation/sitter_profile_page.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

class ProfileApi extends CustomerApi {
  ProfileApi() : super('test', 'sitter');
  Map<String, dynamic> account = {
    '_revision': 7,
    'profile': {'first': 'Server', 'last': 'Sitter', 'photo': null},
    'sitterProfile': {
      'years': 2,
      'about': 'Server care',
      'housing': 'house',
      'homePhotos': [],
      'schedule': {
        'days': [false, true, true, true, true, false, false],
        'start': 600,
        'end': 1020,
      },
    },
    'notifications': {'orders': false, 'chat': true, 'video': false},
    'language': 'uz',
  };
  Map<String, dynamic>? saved;
  bool failWrite = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'PUT') {
      if (failWrite) throw CustomerApiException('Conflict: reload', 409);
      saved = body;
      account = {...body!, '_revision': 8};
    }
    return {'account': account};
  }
}

void main() {
  setUp(() {
    CustomerApi.active = null;
    SharedPreferences.setMockInitialValues({});
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    AppLanguage.current.value = 'uz';
    CustomerApi.active = null;
  });
  Future<void> open(WidgetTester tester, int section) async {
    await tester.pumpWidget(
      AppLanguage(
        child: MaterialApp(
          key: UniqueKey(),
          home: SitterProfilePage(
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

  testWidgets(
    'closed dates survive reload, explicit removal and failed writes; unset hours stay unset',
    (tester) async {
      final api = ProfileApi();
      api.account['sitterProfile'].remove('schedule');
      api.account['sitterProfile']['closedDates'] = ['2026-11-03'];
      CustomerApi.active = api;
      await open(tester, 1);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('handoverHoursEnabled')),
            )
            .value,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('closedDate-2026-11-03')),
        findsOneWidget,
      );
      await save(tester);
      expect(api.saved!['sitterProfile']['schedule'], isNull);
      expect(api.saved!['sitterProfile']['closedDates'], ['2026-11-03']);
      await open(tester, 1);
      final chip = find.byKey(const ValueKey('closedDate-2026-11-03'));
      await tester.ensureVisible(chip);
      tester.widget<InputChip>(chip).onDeleted!();
      await tester.pumpAndSettle();
      api.failWrite = true;
      await save(tester);
      expect(find.text('Conflict: reload'), findsOneWidget);
      expect(api.account['sitterProfile']['closedDates'], ['2026-11-03']);
      api.failWrite = false;
      await save(tester);
      expect(api.account['sitterProfile']['closedDates'], isEmpty);
      await open(tester, 1);
      final add = find.byKey(const ValueKey('addClosedDate'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      await save(tester);
      expect(api.account['sitterProfile']['closedDates'], hasLength(1));
    },
  );

  testWidgets('profile edits persist', (tester) async {
    await open(tester, 0);
    await tester.enterText(find.byKey(const ValueKey('profileFirst')), 'Umar');
    await tester.enterText(
      find.byKey(const ValueKey('profileAbout')),
      'It va mushuklarni parvarish qilaman.',
    );
    await tester.enterText(find.byKey(const ValueKey('profileYears')), '2');
    await save(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mock.profile.first'), 'Umar');
    expect(
      prefs.getString('mock.profile.about'),
      'It va mushuklarni parvarish qilaman.',
    );
  });
  testWidgets(
    'server optional profile values open and save without inventing experience',
    (tester) async {
      final api = ProfileApi();
      api.account['profile'] = {
        'first': 'O‘zbek 😀',
        'last': 'Яна',
        'photo': null,
      };
      api.account['sitterProfile'] = {
        'years': null,
        'about': '',
        'homePhotos': [],
        'housing': 'apartment',
      };
      CustomerApi.active = api;
      await open(tester, 0);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('profileYears')))
            .controller!
            .text,
        isEmpty,
      );
      await save(tester);
      expect(api.saved!['profile']['first'], 'O‘zbek 😀');
      expect(api.saved!['sitterProfile']['years'], isNull);
      expect(api.saved!['sitterProfile']['about'], '');
      expect(api.saved!['_revision'], 7);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('overlong profile name is rejected before a server write', (
    tester,
  ) async {
    final api = ProfileApi();
    CustomerApi.active = api;
    await open(tester, 0);
    await tester.enterText(
      find.byKey(const ValueKey('profileFirst')),
      'a' * 101,
    );
    await save(tester);
    expect(api.saved, isNull);
    expect(find.text('Eng ko‘pi 100 belgi'), findsOneWidget);
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
  testWidgets('help does not pretend to submit while service is unavailable', (
    tester,
  ) async {
    await open(tester, 4);
    await tester.enterText(
      find.byKey(const ValueKey('supportMessage')),
      'Sinov murojaati',
    );
    await save(tester);
    expect(
      (await SharedPreferences.getInstance()).getString('mock.support.message'),
      isNull,
    );
    expect(find.text('Murojaatlar xizmati hali ulanmagan.'), findsOneWidget);
  });
  testWidgets(
    'server notification preferences override local mock settings and save remotely',
    (tester) async {
      SharedPreferences.setMockInitialValues({'mock.notify.orders': true});
      final api = ProfileApi();
      CustomerApi.active = api;
      await open(tester, 3);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('notifyOrders')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('notifyOrders')));
      await save(tester);
      expect(api.saved!['_revision'], 7);
      expect(api.saved!['notifications']['orders'], isTrue);
      expect(api.saved!['notifications']['video'], isFalse);
    },
  );
  testWidgets(
    'schedule loads server values and language only changes after server confirmation',
    (tester) async {
      final api = ProfileApi();
      CustomerApi.active = api;
      await open(tester, 1);
      await tester.tap(find.byKey(const ValueKey('workDay-0')));
      await save(tester);
      expect(api.saved!['sitterProfile']['schedule']['days'][0], isTrue);
      expect(api.saved!['sitterProfile']['schedule']['start'], 600);
      await open(tester, 5);
      api.failWrite = true;
      await tester.tap(find.byKey(const ValueKey('language-ru')));
      await tester.pumpAndSettle();
      expect(AppLanguage.current.value, 'uz');
      expect(find.text('Conflict: reload'), findsOneWidget);
      api.failWrite = false;
      await tester.tap(find.byKey(const ValueKey('language-ru')));
      await tester.pumpAndSettle();
      expect(AppLanguage.current.value, 'ru');
      expect(api.saved!['language'], 'ru');
    },
  );
}
