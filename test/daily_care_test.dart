import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/care/presentation/daily_care_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('tasks are independent per pet and persist after reopening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final date = DateTime(2026, 10, 12, 10);
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(home: DailyCarePage(clock: () => date)),
      );
      await tester.pumpAndSettle();
    }

    await open();
    final meal = find.byKey(const ValueKey('care-meal-0'));
    await tester.ensureVisible(meal);
    await tester.tap(meal);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(meal).value, isTrue);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('care-pet-MQ-0241')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(meal).value, isFalse);
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(tester.widget<CheckboxListTile>(meal).value, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('new day resets tasks and out of window video stays incomplete', (
    tester,
  ) async {
    var date = DateTime(2026, 10, 12, 14);
    await tester.pumpWidget(
      MaterialApp(home: DailyCarePage(clock: () => date)),
    );
    await tester.pumpAndSettle();
    final meal = find.byKey(const ValueKey('care-meal-0'));
    await tester.ensureVisible(meal);
    await tester.tap(meal);
    await tester.pumpAndSettle();
    final video = find.byKey(const ValueKey('video-am'));
    await tester.scrollUntilVisible(
      video,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(video);
    await tester.pumpAndSettle();
    await tester.tap(video);
    await tester.pumpAndSettle();
    expect(
      find.text('Video 06:00–12:00 oralig‘ida qo‘shiladi.'),
      findsOneWidget,
    );
    date = DateTime(2026, 10, 13, 8);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      meal,
      -350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<CheckboxListTile>(meal).value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty care plan has an empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DailyCarePage(pets: [])));
    await tester.pumpAndSettle();
    expect(find.text('Hozircha parvarishdagi hayvonlar yo‘q'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
