import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_availability.dart';

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  Future<void> open(WidgetTester tester, Map<String, dynamic> sitter) async {
    final store = CustomerStore();
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: CustomerAvailability(store: store, sitter: sitter),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'availability and schedule are localized at large text, $language',
      (tester) async {
        AppLanguage.current.value = language;
        await open(tester, {
          'id': 'test',
          'service': 0,
          'availabilityKnown': true,
          'freeCapacity': 1,
          'availabilityInterval': {
            'startsAt': '2026-11-01T18:00:00Z',
            'endsAt': '2026-11-02T18:00:00Z',
          },
        });
        expect(
          find.textContaining(
            {
              'uz': '1 ta bo‘sh joy',
              'en': '1 place available',
              'ru': 'Свободных мест на выбранные даты: 1',
            }[language]!,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('23:00'), findsOneWidget);
        await open(tester, {
          'id': 'test',
          'service': 0,
          'availabilityKnown': false,
          'availability': {
            'schedule': {
              'days': [true, false, false, false, true, false, false],
              'start': 540,
              'end': 1080,
            },
            'closedDates': ['2026-11-03'],
          },
        });
        expect(
          find.textContaining(
            {'uz': 'Du, Ju', 'en': 'Mon, Fri', 'ru': 'Пн, Пт'}[language]!,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('09:00–18:00'), findsOneWidget);
        expect(find.textContaining('2026-11-03'), findsOneWidget);
        expect(
          find.textContaining(
            {
              'uz': 'Tunda qolish mumkin.',
              'en': 'Overnight stays are allowed.',
              'ru': 'Можно оставаться на ночь.',
            }[language]!,
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'incomplete or invalid capacity never falls back to invented local space',
    (tester) async {
      AppLanguage.current.value = 'en';
      for (final free in [null, '3', -1, 31]) {
        await open(tester, {
          'id': 'test',
          'service': 0,
          'availabilityKnown': true,
          'freeCapacity': free,
          'capacity': 3,
          'occupied': 0,
        });
        expect(
          find.text('Availability has not been confirmed yet'),
          findsOneWidget,
        );
        expect(find.textContaining('3 ta joy'), findsNothing);
        expect(find.textContaining('available for the selected'), findsNothing);
      }
    },
  );

  testWidgets('zero home visit availability is not presented as free', (
    tester,
  ) async {
    AppLanguage.current.value = 'en';
    await open(tester, {
      'id': 'test',
      'service': 1,
      'availabilityKnown': true,
      'freeCapacity': 0,
    });
    expect(find.text('No availability for the selected dates'), findsOneWidget);
    expect(find.textContaining('No overlapping visit'), findsNothing);
  });
}
