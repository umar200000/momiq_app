import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';

typedef PositionRequest = Future<Position> Function(LocationSettings settings);

class PositionQualityException implements Exception {
  const PositionQualityException();
}

/// A poor or stale fix must not silently become somebody's precise care address.
Position validateCurrentPosition(Position position, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(position.timestamp);
  if (!position.latitude.isFinite ||
      !position.longitude.isFinite ||
      position.latitude.abs() > 90 ||
      position.longitude.abs() > 180 ||
      !position.accuracy.isFinite ||
      position.accuracy < 0 ||
      position.accuracy > 100 ||
      age > const Duration(minutes: 5) ||
      age < const Duration(minutes: -1)) {
    throw const PositionQualityException();
  }
  return position;
}

/// Retry through Android's native provider when the fused provider times out.
Future<Position> resolveCurrentPosition({
  PositionRequest? request,
  bool? android,
}) async {
  final fetch =
      request ??
      (settings) => Geolocator.getCurrentPosition(locationSettings: settings);
  try {
    return validateCurrentPosition(
      await fetch(
        const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      ).timeout(const Duration(seconds: 20)),
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
    return validateCurrentPosition(
      await fetch(fallback).timeout(const Duration(seconds: 25)),
    );
  }
}
