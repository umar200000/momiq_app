import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';

typedef PositionRequest = Future<Position> Function(LocationSettings settings);

/// Retry through Android's native provider when the fused provider times out.
Future<Position> resolveCurrentPosition({
  PositionRequest? request,
  bool? android,
}) async {
  final fetch =
      request ??
      (settings) => Geolocator.getCurrentPosition(locationSettings: settings);
  try {
    return await fetch(
      const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  } on TimeoutException {
    final LocationSettings fallback = (android ?? Platform.isAndroid)
        ? AndroidSettings(
            forceLocationManager: true,
            accuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 25),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 25),
          );
    return fetch(fallback);
  }
}
