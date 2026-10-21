import 'feed_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_page.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';

void main() {
  testWidgets('client design preview', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = CustomerStore(
      feedRepository: const FixtureCustomerFeedRepository(),
    );
    await store.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final weight in [400, 600]) {
      await (FontLoader(
        'Quicksand',
      )..addFont(rootBundle.load('assets/fonts/Quicksand-$weight.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final key = GlobalKey();
    Future<void> render(Widget page, String path) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          theme: ThemeData(
            fontFamily: 'Quicksand',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFDFA33D),
            ),
          ),
          home: RepaintBoundary(key: key, child: page),
        ),
      );
      await tester.runAsync(() async {
        for (final asset in [
          'customer_service_art.png',
          'customer_home_gallery.png',
          'home_pet_pair.png',
          'customer_sitters.png',
          'customer_home.png',
          'service_cat.png',
          'service_dog.png',
        ]) {
          await precacheImage(
            AssetImage('assets/images/$asset'),
            key.currentContext!,
          );
        }
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      if (page is CustomerHomePage) {
        await tester.drag(
          find.byKey(const ValueKey('customerTab-0')),
          const Offset(0, -520),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/customer-home-cards-preview.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }

    await render(
      CustomerHomePage(store: store),
      'build/customer-home-preview.png',
    );
    await render(
      SitterDetailPage(store: store, sitter: customerSitters.first),
      'build/customer-sitter-preview.png',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
