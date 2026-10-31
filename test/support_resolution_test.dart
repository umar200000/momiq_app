import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/support/support_resolution.dart';

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'historical decision remains readable at 320px and 2x in $language',
      (tester) async {
        AppLanguage.current.value = language;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(
                  child: SupportResolution(
                    value: {
                      'snapshot': {
                        'kind': 'listing',
                        'available': true,
                        'status': 'rejected',
                        'sourceRevision': 12,
                        'decision': {
                          'reason': '<script>TEST inert saved reason</script>',
                        },
                      },
                      'sourceEvent': 'PRIVATE ADMIN REFERENCE',
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('<script>TEST inert saved reason</script>'),
          findsOneWidget,
        );
        expect(find.textContaining('PRIVATE ADMIN'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            language == 'uz'
                ? 'Rad etilgan'
                : language == 'en'
                ? 'Rejected'
                : 'Отклонено',
          ),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'review withdrawal is separate and incomplete visibility is not claimed restored',
    (tester) async {
      Future<void> show(Map<String, Object?> snapshot) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportResolution(value: {'snapshot': snapshot}),
          ),
        ),
      );
      await show({
        'kind': 'review',
        'available': true,
        'hidden': false,
        'withdrawn': true,
      });
      expect(find.text('Moderatsiya cheklovi yo‘q'), findsOneWidget);
      expect(find.text('Muallif yashirgan'), findsOneWidget);
      await show({'kind': 'review', 'available': true});
      expect(find.text('Moderatsiya cheklovi yo‘q'), findsNothing);
      expect(find.textContaining('Qaror nusxasi o‘qilmadi'), findsOneWidget);
      await show({'kind': 'listing', 'available': false});
      expect(find.text('Manba mavjud emas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
