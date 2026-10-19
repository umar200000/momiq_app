# Momiq app

Flutter application for pet owners and pet sitters.

## Local setup

1. Install Flutter and run `flutter pub get`.
2. Copy `lib/core/config/maps_key.example.dart` to `lib/core/config/maps_key.local.dart`.
3. Set your Yandex MapKit key in the local file, or pass `--dart-define=YANDEX_MAPKIT_API_KEY=YOUR_KEY` (the local file must still exist).
4. Start the separate Momiq backend on port 8080.
5. For a USB-connected Android phone, run `adb reverse tcp:8080 tcp:8080`.
6. Run `flutter run`. Override the API URL with `--dart-define=MOMIQ_API_URL=https://your-server/api` when needed.

The localhost backend uses development verification code `111111`; real SMS is not connected. Client profile and chat use the backend. Other flows still include mock data.

## Checks

```sh
flutter analyze
flutter test
```

The live API integration test is opt-in: `flutter test --dart-define=MOMIQ_INTEGRATION=true test/customer_api_integration_test.dart`.

Credentials, signing keys, build outputs and local configuration are excluded from Git. Do not commit the local MapKit key.
