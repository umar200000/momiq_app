import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../../listings/data/current_position.dart';
import 'customer_feed_repository.dart';

enum CustomerLocationStatus {
  unsupported,
  disabled,
  denied,
  deniedForever,
  ready,
}

class CustomerLocationService {
  Future<CustomerLocationStatus> status() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return CustomerLocationStatus.unsupported;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return CustomerLocationStatus.disabled;
    }
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always ||
      LocationPermission.whileInUse => CustomerLocationStatus.ready,
      LocationPermission.deniedForever => CustomerLocationStatus.deniedForever,
      _ => CustomerLocationStatus.denied,
    };
  }

  Future<void> requestPermission() async {
    await Geolocator.requestPermission();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<CustomerCoordinates> locate() async {
    final p = await resolveCurrentPosition();
    return CustomerCoordinates(p.latitude, p.longitude);
  }
}
