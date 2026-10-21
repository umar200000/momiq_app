import 'feed_fixture.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/data/customer_location_service.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_page.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';

class NoLocation extends CustomerLocationService {
  @override
  Future<CustomerLocationStatus> status() async =>
      CustomerLocationStatus.unsupported;
}

void main() {
  testWidgets('shared backdrop has ten paws behind tappable content', (
    t,
  ) async {
    var tapped = false;
    await t.pumpWidget(
      MaterialApp(
        home: MomiqScaffold(
          body: Center(
            child: TextButton(
              onPressed: () => tapped = true,
              child: const Text('Tap'),
            ),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(MomiqPawBackdrop),
        matching: find.byType(SvgPicture),
      ),
      findsNWidgets(10),
    );
    await t.tap(find.text('Tap'));
    expect(tapped, isTrue);
    expect(t.takeException(), isNull);
  });
  testWidgets('client cat uses same physical bottom position as sitter cat', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    t.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(t.view.reset);
    final store = CustomerStore(
      feedRepository: const FixtureCustomerFeedRepository(delay: Duration.zero),
    );
    await store.load();
    final previewKey = GlobalKey();
    Future<double> catBottom(Widget home) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(key: previewKey, child: home),
        ),
      );
      await t.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/edge_pet_variants.png'),
          previewKey.currentContext!,
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 30));
      if (home is CustomerHomePage) {
        await t.tap(find.byKey(const ValueKey('customerNav-2')));
        await t.pump();
      }
      await t.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('edgeCat')), findsOneWidget);
      expect(find.byType(MomiqPawBackdrop), findsOneWidget);
      expect(find.byKey(const ValueKey('petVisitorsOverlay')), findsOneWidget);
      if (home is CustomerHomePage) {
        await t.runAsync(() async {
          final image =
              await (previewKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/client-cat-visible.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      return t.getBottomLeft(find.byKey(const ValueKey('edgeCat'))).dy;
    }

    final sitter = await catBottom(
      SitterHomePage(
        avatar: File('assets/images/myid_pets.png').readAsBytesSync(),
      ),
    );
    final client = await catBottom(
      CustomerHomePage(store: store, locationService: NoLocation()),
    );
    expect(client, closeTo(sitter, .1));
    await t.pumpWidget(const SizedBox());
    store.dispose();
  });
}
