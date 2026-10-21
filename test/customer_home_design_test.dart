import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_design.dart';

void main() {
  testWidgets('carousel advances automatically and supports manual swiping', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomerBannerCarousel())),
    );
    await t.pump();
    final pager = t.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.page, 0);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 500));
    expect(pager.controller!.page, 1);
    await t.drag(find.byType(PageView), const Offset(-700, 0));
    await t.pumpAndSettle();
    expect(pager.controller!.page, 2);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'all service cards are equal at narrow width and remain tappable',
    (t) async {
      t.view.physicalSize = const Size(320, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      int? selected;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: CustomerServiceTiles(onSelected: (i) => selected = i),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final sizes = [
        for (var i = 0; i < 3; i++)
          t.getSize(find.byKey(ValueKey('customerService-$i'))),
      ];
      expect(sizes[0].width, closeTo(sizes[1].width, .01));
      expect(sizes[0].height, closeTo(sizes[1].height, .01));
      expect(sizes[1].width, closeTo(sizes[2].width, .01));
      expect(sizes[1].height, closeTo(sizes[2].height, .01));
      await t.tap(find.byKey(const ValueKey('customerService-2')));
      expect(selected, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('numeric demo gallery references do not render photos', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerHomePhotos(
            sitter: {
              'id': 'old',
              'homePhotos': [0, 1, 2],
            },
          ),
        ),
      ),
    );
    expect(find.byType(CustomerAtlasArt), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(t.takeException(), isNull);
  });
}
