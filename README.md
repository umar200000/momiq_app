# Momiq app

Current development builds default to `http://127.0.0.1:8080/api` with `MOMIQ_ENV=local`. Use `config/local.json` or explicit defines; `config/production.json` is reserved for the final production build. Hosted staging requires its own URL and `MOMIQ_ENV=staging`. Unknown/other-environment sessions are cleared before reuse. Production login requires real SMS and rejects a server advertising test login. See the sibling backend's `LOCAL_DEVELOPMENT.md` and `PRODUCTION_CHECKLIST.md` for current setup and progress.

Flutter application for pet owners and pet sitters.

## Local setup

1. Install Flutter and run `flutter pub get`.
2. Copy `lib/core/config/maps_key.example.dart` to `lib/core/config/maps_key.local.dart`.
3. Set your Yandex MapKit key in the local file, or pass `--dart-define=YANDEX_MAPKIT_API_KEY=YOUR_KEY` (the local file must still exist).
4. Start the separate Momiq backend on port 8080.
5. For a USB-connected Android phone, run `adb reverse tcp:8080 tcp:8080`.
6. Run `flutter run`. Override the API URL with `--dart-define=MOMIQ_API_URL=https://your-server/api` when needed.

The localhost backend uses development verification code `111111`; real SMS is not connected. Client profile and chat use the backend. The catalog is loaded from the backend. No demonstration users, sitters, bookings or reviews are seeded.

## Checks

```sh
flutter analyze
flutter test
```

The live API integration test is opt-in: `flutter test --dart-define=MOMIQ_INTEGRATION=true test/customer_api_integration_test.dart`.

Credentials, signing keys, build outputs and local configuration are excluded from Git. Do not commit the local MapKit key.

## Hosted test environment

The existing hosted test server is `https://api.momiq.net/api`; it is not a production-ready customer launch. New environment-guarded builds must use a separate staging endpoint for hosted test login. SMS integration and production signing are deferred to the final phase.

For localhost use `flutter run --dart-define=MOMIQ_API_URL=http://127.0.0.1:8080/api` and USB adb reverse. Run local live integration tests with the same URL override. GitHub Actions runs analysis and tests on pushes/PRs; mobile store releases/signing are not configured.

## Data availability

The backend sitter catalog starts empty. Listing publication, booking/payment processing, sitter chat and MyID verification are not connected yet; these must not claim success. Sitter service/profile drafts entered by the user remain device-local. Demo dashboards, reviews, care reports and invented photos/addresses were removed. Only the explicitly enabled login code 111111 remains simulated. Test fixtures are confined to test/.

## Session lifecycle

OTP login returns the existing server account. Completed profiles go straight to the selected role home; incomplete profiles resume registration. The token, selected role and last account snapshot persist across app restarts. Startup validates the session with `/api/me`; network failures keep the saved login, while expired/blocked sessions return to role selection.

Logout revokes the current session when the server is reachable and clears this device's account/session caches, pets, sitter drafts and copied care videos. The server account remains intact. Offline logout still clears the device; the unreachable server session expires normally. Other devices' sessions are unaffected. Sitter registration data is saved to the account, but publishing a sitter listing remains separate.
