import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/video_picker_cache.dart';

void main() {
  test(
    'only disposable app temp copies are removed; external originals survive',
    () async {
      final root = await Directory.systemTemp.createTemp('momiq-picker-test-');
      addTearDown(() => root.delete(recursive: true));
      final cache = await Directory('${root.path}/app-cache').create();
      final copy = await File(
        '${cache.path}/video.mp4',
      ).writeAsString('TEST COPY');
      final original = await File(
        '${root.path}/original.mp4',
      ).writeAsString('TEST ORIGINAL');
      expect(
        await discardVideoPickerCopy(
          original.path,
          temporary: () async => cache,
        ),
        false,
      );
      expect(await original.readAsString(), 'TEST ORIGINAL');
      expect(
        await discardVideoPickerCopy(copy.path, temporary: () async => cache),
        true,
      );
      expect(await copy.exists(), false);
    },
  );
}
