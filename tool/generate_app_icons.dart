// Run with: flutter test tool/generate_app_icons.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:momiq_app/core/widgets/momiq_logo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('export splash branding for native launchers', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    Future<void> render({bool foreground = false}) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Color(0xFFE0A247),
              child: Center(child: MomiqLogo(size: foreground ? 740 : 880)),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(MomiqLogo.asset),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> save(String path, int size) async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: size / 1024);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await render();
    await save('assets/branding/momiq-icon-1024.png', 1024);
    const densities = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in densities.entries) {
      await save(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
      );
    }
    final catalog =
        jsonDecode(
              File(
                'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final item in catalog['images'] as List) {
      final size = double.parse((item['size'] as String).split('x').first);
      final scale = double.parse((item['scale'] as String).replaceAll('x', ''));
      await save(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/${item['filename']}',
        (size * scale).round(),
      );
    }
    await render(foreground: true);
    for (final entry in {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    }.entries) {
      await save(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png',
        entry.value,
      );
    }
  });
}
