import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:map_launcher/map_launcher_platform_interface.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_design.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';
import 'package:momiq_app/features/listings/presentation/external_map_picker.dart';

class FakeMaps extends MapLauncherPlatform {
  Set<String> installed = {MapApp.google.id, MapApp.yandexMaps.id};
  String? launched, package;
  bool fail = false;
  @override
  MapPlatform get platform => MapPlatform.android;
  @override
  Future<Set<String>> getInstalledMaps(List<MapApp> maps) async => installed;
  @override
  Future<void> launch(String url, {String? androidPackageName}) async {
    if (fail) throw StateError('Cannot launch');
    launched = url;
    package = androidPackageName;
  }
}

void main() {
  testWidgets(
    'all photos wrap, count matches, gallery swipes from selected photo',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerHomePhotos(
                sitter: {
                  'id': 'test',
                  'homePhotos': List.filled(5, base64Encode(File('assets/images/service_cat.png').readAsBytesSync())),
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('5 ta rasm'), findsOneWidget);
      final first = find.byKey(const ValueKey('sitterHomePhoto-test-0'));
      final fourth = find.byKey(const ValueKey('sitterHomePhoto-test-3'));
      expect(t.getTopLeft(fourth).dy, greaterThan(t.getBottomLeft(first).dy));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      await t.tap(fourth);
      await t.pumpAndSettle();
      expect(find.text('4 / 5'), findsOneWidget);
      await t.drag(
        find.byKey(const ValueKey('homePhotoGallery')),
        const Offset(-300, 0),
      );
      await t.pumpAndSettle();
      expect(find.text('5 / 5'), findsOneWidget);
      await t.drag(
        find.byKey(const ValueKey('homePhotoGallery')),
        const Offset(300, 0),
      );
      await t.pumpAndSettle();
      expect(find.text('4 / 5'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  const location = CareLocation(
    latitude: 41.2995,
    longitude: 69.2726,
    address: 'Oybek ko‘chasi, 12',
  );
  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExternalMapPicker(context, location),
              child: const Text('Map'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Map'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'picker lists only installed maps and opens chosen app at destination',
    (t) async {
      final previous = MapLauncherPlatform.instance;
      final platform = FakeMaps();
      MapLauncherPlatform.instance = platform;
      addTearDown(() => MapLauncherPlatform.instance = previous);
      await open(t);
      expect(find.text('Google Maps'), findsOneWidget);
      expect(
        find.byKey(ValueKey('externalMap-${MapApp.apple.id}')),
        findsNothing,
      );
      await t.tap(find.byKey(ValueKey('externalMap-${MapApp.google.id}')));
      await t.pumpAndSettle();
      expect(platform.launched, contains('41.2995'));
      expect(platform.launched, contains('69.2726'));
      expect(platform.package, 'com.google.android.apps.maps');
      expect(find.byType(ExternalMapPicker), findsNothing);
    },
  );
  testWidgets('no maps and failed launch have recoverable messages', (t) async {
    final previous = MapLauncherPlatform.instance;
    final platform = FakeMaps()..installed = {};
    MapLauncherPlatform.instance = platform;
    addTearDown(() => MapLauncherPlatform.instance = previous);
    await open(t);
    expect(find.textContaining('Navigator topilmadi'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    platform.installed = {MapApp.google.id};
    platform.fail = true;
    await open(t);
    await t.tap(find.byKey(ValueKey('externalMap-${MapApp.google.id}')));
    await t.pumpAndSettle();
    expect(find.textContaining('Navigator ochilmadi'), findsOneWidget);
    expect(find.byType(ExternalMapPicker), findsOneWidget);
    platform.fail = false;
    await t.tap(find.byKey(ValueKey('externalMap-${MapApp.google.id}')));
    await t.pumpAndSettle();
    expect(find.byType(ExternalMapPicker), findsNothing);
  });
}
