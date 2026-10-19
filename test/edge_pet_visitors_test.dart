import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/widgets/edge_pet_visitors.dart';

void main() {
  testWidgets('pets alternate, disappear and pass touches through', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => taps++,
                  behavior: HitTestBehavior.opaque,
                ),
              ),
              const Positioned.fill(child: EdgePetVisitors()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('edgeDog')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('edgeDog')), findsOneWidget);
    expect(find.byKey(const ValueKey('edgeCat')), findsNothing);
    await tester.tapAt(const Offset(35, 160));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('edgeDog')), findsNothing);
    expect(find.byKey(const ValueKey('edgeCat')), findsNothing);
    await tester.pump(const Duration(seconds: 26));
    expect(find.byKey(const ValueKey('edgeCat')), findsOneWidget);
    expect(find.byKey(const ValueKey('edgeDog')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('edgeCat')), findsNothing);
    await tester.pump(const Duration(seconds: 26));
    expect(find.byKey(const ValueKey('edgeVariant-2')), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const ValueKey('edgeVariant-3')), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const ValueKey('edgeVariant-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion hides visitors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: EdgePetVisitors(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edgeDog')), findsNothing);
    expect(find.byKey(const ValueKey('edgeCat')), findsNothing);
  });
}
