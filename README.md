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

The backend sitter catalog starts empty. Listings and profiles are revisioned server data. Admin moderation can publish explicitly marked test listings outside production; MyID approval and real date availability remain unfinished. Booking/commission processing must not claim success. Participant chat now uses the authenticated conversation API; moderation, booking linkage and physical device verification remain open. Demo dashboards, reviews, care reports and invented photos/addresses were removed. Login code `111111` is confined to an explicitly enabled test environment.

## Manual wallet payment drafts

Opening a payment QR first persists its version, recipient and instructions on this device. New receipt submissions require the payment time or transaction ID shown by the provider. The user supplies these as evidence; they do not pre-fill the admin's verified transfer ID. Amount, receipt and stable retry ID are saved in an AES-256-GCM authenticated file in the app support directory. A device-only secure-storage key and account/API URL binding isolate drafts. If a write fails the initial QR remains hidden; subsequent save failures are shown with a retry action. Corrupt drafts are preserved until explicitly discarded. Consent must be reconfirmed after reopening.

A successful server response clears the draft. A lost response preserves the same request ID for a safe retry; the server credits nothing until an admin verifies actual incoming funds. Signing out or clearing an incompatible session removes the local encrypted files and key. Drafts do not survive uninstall, logout or device loss; the original provider receipt remains the recovery evidence. No real payment should be made through local TEST QR images.

Rejected requests and requests needing clarification open an amendment form with their original QR/evidence revision. It explicitly asks the sitter not to pay again. Amendment drafts have separate encrypted storage from new-payment drafts. The original QR, stable retry ID and renewed consent are preserved across restart. Stale form revisions cannot change current evidence. Request history loads older snapshots and images on demand. A successful server submission followed by local cleanup failure offers cleanup retry without posting a second request.

## Session lifecycle

The customer and sitter bell buttons open server-backed notification history. Wallet and listing review events paginate, retain read state and open only known local wallet/listing destinations. Existing decisions before migration 6 have no retroactive notice. External push and booking/chat/care notifications remain unfinished; optional order/chat/care preferences do not hide transactional wallet/moderation history.

OTP login returns the existing server account. Completed profiles go straight to the selected role home; incomplete profiles resume registration. The token, selected role and last account snapshot persist across app restarts. Startup validates the session with `/api/me`; network failures keep the saved login, while expired/blocked sessions return to role selection.

Logout revokes the current session when the server is reachable and clears this device's account/session caches, pets, sitter drafts and copied care videos. The server account remains intact. Offline logout still clears the device; the unreachable server session expires normally. Other devices' sessions are unaffected. Sitter registration data is saved to the account, but publishing a sitter listing remains separate.


Payment QR media: the original draft QR can be enlarged or explicitly saved to the system gallery with `gal` 2.3.3. Only the operator QR is exported; private receipts stay in the encrypted draft and authenticated API. Saved QR files remain outside the app after logout, so the screen instructs users to fetch the current QR before each new payment. Gallery permission denial/storage failure never reports success. Receipt selection offers camera/gallery, requests no full metadata, and validates PNG/JPEG/WebP size, dimensions and decoding before replacing the previous evidence. iOS add-only photo permission and Android legacy write permission (API <=29 only) are declared. Before launching the external picker, an encrypted interruption marker preserves the prior evidence. If the process dies, the wallet requires explicit reselection before submission; cancellation does not bypass that requirement. Global lost-picker data is never automatically attached across profile/pet/payment flows. Native process-death verification and physical iPhone permission/media checks remain open in M139.


## Participant chat

Customer and sitter chat tabs use the same authenticated conversation inbox. A listing contact button creates a server-validated conversation. Only participants can read/write; admin support history is labelled separately. History pages use server sequence cursors, images load on demand, and the peer read marker controls the Read label. Sent means accepted by the server, not delivered to a device.

Active chat polls only deltas every five seconds and inbox metadata every ten seconds. Background or covered routes stop polling; switching tabs disposes their timer. The former global three-second account/full-message poll was removed. Before POST, the exact message and random request ID are saved with the existing AES-GCM storage implementation under a separate account/API/conversation scope. Failed response or restart locks that request for exact retry. The same logout cleanup removes these encrypted outboxes. Typing and image selection before Send remain in memory; this limitation must be kept visible in release review. New sent messages never advance the incoming cursor, so a concurrently received message cannot be skipped.

Local API/widget tests cover ownership, retry/restart, concurrent send, pagination, read markers and lifecycle. Native screenshot capture is currently unavailable (black emulator capture); no physical Android/iOS chat acceptance is claimed. Booking linkage, external push and full operator role separation remain unfinished.


Chat safety controls: each incoming message can be reported with a reason; the chat menu offers pair-wide block/unblock and own report history. Reporting does not automatically block. Moderator redactions arrive on a separate change cursor, including changes to already-loaded messages; a stale response cannot restore hidden content. A pending outbox can be explicitly cleared after a warning that this is not a recall. Admin decisions and evidence access are audited. Native chat/media verification and dedicated moderator permissions remain release gates.


Authenticated pet management now supports archive/restore with account revisions, an archive list and active-only booking selection. Failed requests do not hide a pet optimistically. Remote records survive account/store reload; unauthenticated preview pets intentionally remain session-only. Old booking metadata is retained by the backend snapshot layer. Local/test catalog records with `bookingEnabled=true` open the four-step server-quote booking flow. Both roles have real paginated booking lists/details; sitter accept/reject and prestart cancellation use revisioned, encrypted retry commands. Exact price and commission come from the immutable server quote. Started-24-hour pricing and fixed daily home-visit fees follow the approved policy. Full service start/end, no-show disputes, booking notices and public production rollout remain open.

## Booking communication and notices

Local/test booking details open the existing customer/sitter/service conversation for either participant. The chat menu lists only bookings shared in that service, with pagination and server-side access checks. Low sitter balance does not interrupt an existing agreement's chat. A closed request that was never accepted cannot create new contact.

Committed booking status changes appear in the in-app notification list and open the exact booking after its server ID is validated. External push/SMS is not yet connected. The local/test server now expires unanswered requests in the background; the app does not have to remain open. See the backend checklist for lifecycle and release gates.

Local/test booking details also support separate start and completion confirmations from each participant. One confirmation waits for the other party; only both confirmations activate or complete care. Start is limited to the agreed interval, early completion keeps the agreed price, and these actions never debit another commission. Pending commands survive restart in the encrypted booking outbox. Native two-party acceptance remains a checklist verification item; isolated HTTP and widget tests cover the transitions.
