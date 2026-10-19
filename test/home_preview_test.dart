import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';

void main() {
  testWidgets('home design preview', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final font = FontLoader('Quicksand')
      ..addFont(rootBundle.load('assets/fonts/Quicksand-400.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Quicksand-600.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(key: key, child: const SitterHomePage()),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/home_pet_pair.png'),
        key.currentContext!,
      );
    });
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/home-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  });
}
