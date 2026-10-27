# Momiq app

Current development builds default to `http://127.0.0.1:8080/api` with `MOMIQ_ENV=local`. Use `config/local.json` or explicit defines; `config/production.json` is reserved for the final production build. Hosted staging requires its own URL and `MOMIQ_ENV=staging`. Unknown/other-environment sessions are cleared before reuse. Production login requires real SMS and rejects a server advertising test login. See the sibling backend's `LOCAL_DEVELOPMENT.md` and `PRODUCTION_CHECKLIST.md` for current setup and progress.

Flutter application for pet owners and pet sitters.

## Local setup

1. On Windows run `./tool/setup-flutter.ps1`, then `./tool/flutter.ps1 pub get --enforce-lockfile`. This installs the pinned Flutter 3.44.5 in the project without replacing the global SDK. Other hosts should use `.flutter-version`.
2. Copy `lib/core/config/maps_key.example.dart` to `lib/core/config/maps_key.local.dart`.
3. Set your Yandex MapKit key in the local file, or pass `--dart-define=YANDEX_MAPKIT_API_KEY=YOUR_KEY` (the local file must still exist).
4. Start the separate Momiq backend with `./start.ps1 -Port 8081 -Seed` after its Python setup.
5. For a USB-connected Android device, run `adb reverse tcp:8081 tcp:8081`.
6. Run `./tool/flutter.ps1 run --dart-define-from-file=config/preview.json`. `config/local.json` still targets port 8080; preview uses the isolated database on 8081. Changing the API URL clears an existing session by design.

The localhost backend uses development verification code `111111`; real SMS is not connected. `-Seed` explicitly creates marked test accounts in an isolated preview database; production never auto-seeds them. Profile, preferences and manual Paynet Xolis top-up requests use the backend. Booking/commission integration and real sitter publication are still incomplete.

## Checks

```sh
./tool/flutter.ps1 analyze
./tool/flutter.ps1 test --concurrency=1
```

The live API integration test is opt-in: `./tool/flutter.ps1 test --dart-define=MOMIQ_INTEGRATION=true --dart-define-from-file=config/preview.json test/customer_api_integration_test.dart`.

The Windows wrapper keeps Gradle and temporary build files in `.local/gradle` and `.local/tmp` to avoid filling the system drive. CI checks analysis, tests, an Android ARM64 debug build with Java 21 and an iOS simulator build. Release signing remains deferred. For an x64 Android emulator preview APK, run `./tool/flutter.ps1 build apk --debug --target-platform android-x64 --dart-define-from-file=config/preview.json`.

Credentials, signing keys, build outputs and local configuration are excluded from Git. Do not commit the local MapKit key.

## Hosted test environment

The existing hosted test server is `https://api.momiq.net/api`; it is not a production-ready customer launch. New environment-guarded builds must use a separate staging endpoint for hosted test login. SMS integration and production signing are deferred to the final phase.

For localhost use `flutter run --dart-define=MOMIQ_API_URL=http://127.0.0.1:8080/api` and USB adb reverse. Run local live integration tests with the same URL override. GitHub Actions runs analysis and tests on pushes/PRs; mobile store releases/signing are not configured.

## Data availability

The backend sitter catalog starts empty. Listings and profiles are revisioned server data. Admin moderation can publish explicitly marked test listings outside production; MyID approval and real date availability remain unfinished. Booking/commission processing and sitter chat must not claim success. Demo dashboards, reviews, care reports and invented photos/addresses were removed. Login code `111111` is confined to an explicitly enabled test environment.

## Manual wallet payment drafts

Opening a payment QR first persists its version, recipient and instructions on this device. New receipt submissions require the payment time or transaction ID shown by the provider. The user supplies these as evidence; they do not pre-fill the admin's verified transfer ID. Amount, receipt and stable retry ID are saved in an AES-256-GCM authenticated file in the app support directory. A device-only secure-storage key and account/API URL binding isolate drafts. If a write fails the initial QR remains hidden; subsequent save failures are shown with a retry action. Corrupt drafts are preserved until explicitly discarded. Consent must be reconfirmed after reopening.

A successful server response clears the draft. A lost response preserves the same request ID for a safe retry; the server credits nothing until an admin verifies actual incoming funds. Signing out or clearing an incompatible session removes the local encrypted files and key. Drafts do not survive uninstall, logout or device loss; the original provider receipt remains the recovery evidence. No real payment should be made through local TEST QR images.

Rejected requests and requests needing clarification open an amendment form with their original QR/evidence revision. It explicitly asks the sitter not to pay again. Amendment drafts have separate encrypted storage from new-payment drafts. The original QR, stable retry ID and renewed consent are preserved across restart. Stale form revisions cannot change current evidence. Request history loads older snapshots and images on demand. A successful server submission followed by local cleanup failure offers cleanup retry without posting a second request.

## Session lifecycle

The customer and sitter bell buttons open server-backed notification history. Wallet and listing review events paginate, retain read state and open only known local wallet/listing destinations. Existing decisions before migration 6 have no retroactive notice. External push and booking/chat/care notifications remain unfinished; optional order/chat/care preferences do not hide transactional wallet/moderation history.

OTP login returns the existing server account. Completed profiles go straight to the selected role home; incomplete profiles resume registration. The token, selected role and last account snapshot persist across app restarts. Startup validates the session with `/api/me`; network failures keep the saved login, while expired/blocked sessions return to role selection.

Logout revokes the current session when the server is reachable and clears this device's account/session caches, pets, sitter drafts and copied care videos. The server account remains intact. Offline logout still clears the device; the unreachable server session expires normally. Other devices' sessions are unaffected. Sitter registration data is saved to the account, but publishing a sitter listing remains separate.
