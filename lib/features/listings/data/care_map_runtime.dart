import 'package:yandex_maps_mapkit/init.dart' as yandex;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import '../../../core/config/maps_key.local.dart';

/// Both the inline preview and full-screen picker can own a visible map.
class CareMapRuntime {
  static Future<void>? _initializing;
  static bool _initialized = false;
  static int _visibleViews = 0;
  static Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      const key = String.fromEnvironment(
        'YANDEX_MAPKIT_API_KEY',
        defaultValue: localYandexMapkitKey,
      );
      if (key.isEmpty) throw StateError('Missing MapKit key');
      await yandex.initMapkit(apiKey: key);
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  static void startView() {
    if (_visibleViews++ == 0) mapkit.onStart();
  }

  static void stopView() {
    if (_visibleViews > 0 && --_visibleViews == 0) mapkit.onStop();
  }
}
