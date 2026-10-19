import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/widgets/pressable_button.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/myid_page.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';

void main() {
  testWidgets('press holds scale and fires exactly once only on release', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableButton(
              onPressed: () => taps++,
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressableButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .94);
    await tester.pump(const Duration(seconds: 2));
    expect(taps, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .94);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
  testWidgets('drag outside in any direction cancels even after re-entry', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableButton(
              onPressed: () => taps++,
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(PressableButton));
    for (final offset in [
      const Offset(0, -100),
      const Offset(0, 100),
      const Offset(-200, 0),
      const Offset(200, 0),
    ]) {
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.moveTo(center + offset);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.moveTo(center);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    }
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
  testWidgets('pointer cancellation and disabled buttons do not activate', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableButton(
              onPressed: () => taps++,
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressableButton)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableButton(onPressed: null, child: Text('Go')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
  testWidgets(
    'MyID drag-up cancels navigation; next regular tap opens registration',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(const MaterialApp(home: MyIdPage()));
      final label = find.text('MyID orqali davom etish');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      final center = tester.getCenter(label);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 140));
      await gesture.moveBy(const Offset(0, -120));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(SitterRegistrationPage), findsNothing);
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(find.byType(SitterRegistrationPage), findsOneWidget);
    },
  );
}
