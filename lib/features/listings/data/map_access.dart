import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

class MapAccessState {
  const MapAccessState({required this.location, required this.permission});
  final bool location, permission;
  bool get ready => location && permission;
}

class MapAccessProbe {
  bool get supported => Platform.isAndroid || Platform.isIOS;
  Future<MapAccessState> check() async {
    if (!supported) {
      return const MapAccessState(location: true, permission: true);
    }
    final results = await Future.wait([
      Geolocator.isLocationServiceEnabled(),
      Geolocator.checkPermission().then(
        (p) =>
            p == LocationPermission.always ||
            p == LocationPermission.whileInUse,
      ),
    ]);
    return MapAccessState(location: results[0], permission: results[1]);
  }

  Future<void> resolve(MapAccessState state) async {
    if (!supported) return;
    if (!state.location) {
      await Geolocator.openLocationSettings();
    } else if (!state.permission) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      } else {
        await Geolocator.requestPermission();
      }
    }
  }
}

/// Poll while visible and recheck immediately after returning from device settings.
class MapAccessController extends ChangeNotifier with WidgetsBindingObserver {
  MapAccessController({MapAccessProbe? probe})
    : probe = probe ?? MapAccessProbe();
  final MapAccessProbe probe;
  MapAccessState? state;
  bool checking = false;
  bool _disposed = false;
  bool _foreground = true;
  Future<bool>? _pending;
  Timer? _timer;
  bool get ready => state?.ready == true;
  void start() {
    WidgetsBinding.instance.addObserver(this);
    refresh();
    if (probe.supported) {
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (_foreground) refresh();
      });
    }
  }

  Future<bool> refresh() => _pending ??= _check();
  Future<bool> _check() async {
    checking = true;
    notifyListeners();
    try {
      final result = await probe.check();
      if (!_disposed) state = result;
      return result.ready;
    } catch (_) {
      if (!_disposed) {
        state = const MapAccessState(location: false, permission: false);
      }
      return false;
    } finally {
      _pending = null;
      checking = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resolve() async {
    if (checking || state == null) return;
    try {
      await probe.resolve(state!);
    } on PlatformException {
      // Keep the manual instructions visible when system settings are unavailable.
    }
    if (!_disposed) await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
