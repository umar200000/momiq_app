# Momiq app

Current development builds default to `http://127.0.0.1:8080/api` with `MOMIQ_ENV=local`. Use `config/local.json` or explicit defines; `config/production.json` is reserved for the final production build. Hosted staging requires its own URL and `MOMIQ_ENV=staging`. A saved session from another environment is blocked without transmission or automatic deletion; the matching build can reuse it. Unknown legacy/inconsistent credentials still require fresh sign-in. Production login requires real SMS and rejects a server advertising test login. See the sibling backend's `LOCAL_DEVELOPMENT.md` and `PRODUCTION_CHECKLIST.md` for current setup and progress.

Flutter application for pet owners and pet sitters.

## Local setup

1. On Windows run `./tool/setup-flutter.ps1`, `./tool/setup-java.ps1`, then `./tool/flutter.ps1 pub get --enforce-lockfile`. This installs the pinned Flutter 3.44.5 and checksum-verified Temurin JDK 21 in the project without replacing global tools. Other hosts should use `.flutter-version` and JDK 21 as CI does.
2. Copy `lib/core/config/maps_key.example.dart` to `lib/core/config/maps_key.local.dart`.
3. Set your Yandex MapKit key in the local file, or pass `--dart-define=YANDEX_MAPKIT_API_KEY=YOUR_KEY` (the local file must still exist).
4. Start the separate Momiq backend with `./start.ps1 -Port 8081 -Seed` after its Python setup.
5. For a USB-connected Android device, run `adb reverse tcp:8081 tcp:8081`.
6. Run `./tool/flutter.ps1 run --dart-define-from-file=config/preview.json`. `config/local.json` still targets port 8080; preview uses the isolated database on 8081. Changing the API URL opens a recovery screen and preserves the previous session and encrypted drafts; it never sends those credentials to the new origin.

The localhost backend uses development verification code `111111`; real SMS is not connected. `-Seed` explicitly creates marked test accounts in an isolated preview database; production never auto-seeds them. Profile, preferences and manual Paynet Xolis top-up requests use the backend. Booking/commission integration and real sitter publication are still incomplete.

## Checks

```sh
./tool/flutter.ps1 analyze
./tool/flutter.ps1 test --concurrency=1
```

The live API integration test is opt-in: `./tool/flutter.ps1 test --dart-define=MOMIQ_INTEGRATION=true --dart-define-from-file=config/preview.json test/customer_api_integration_test.dart`.

The Windows wrapper keeps Gradle and temporary build files in `.local/gradle` and `.local/tmp` to avoid filling the system drive. CI checks analysis, tests, an Android ARM64 debug build with Java 21 and an iOS simulator build. Release signing remains deferred. For an x64 Android emulator preview APK, run `./tool/flutter.ps1 build apk --debug --target-platform android-x64 --dart-define-from-file=config/preview.json`.

The wrapper selects the project JDK for the Gradle **daemon/build JVM** using a process-scoped `org.gradle.java.home` system property, restores the original environment on exit, and rejects other major versions. `MOMIQ_JAVA_HOME` can select another JDK 21 security patch. Flutter's launcher/doctor may still report Android Studio's bundled Java; its preference is global and is intentionally left alone. See [Flutter's Java selection documentation](https://docs.flutter.dev/release/breaking-changes/android-java-gradle-migration-guide) and [Adoptium's verified download guidance](https://adoptium.net/installation/ci-scripts). The setup script records the official download URL and SHA-256; it does not silently update binaries.

Current toolchain: Flutter 3.44.5 commit `f94f4fc76b4d74543ed9b085bbd75341ef65de22`, bundled Dart 3.12.2, Gradle 9.1.0, Android Gradle plugin 9.0.1, Kotlin 2.3.20, Java build runtime 21 / source target 17, compile/target SDK 36, min SDK 26, NDK 28.2.13676358 (SDK/NDK values derive from the pinned Flutter extension). `pubspec.lock` is committed. iOS uses Flutter-generated local Swift packages, not a committed CocoaPods lockfile; the pinned Yandex package includes its 4.45.0 binary URL/checksum. CI and the local wrapper use the same Flutter version; dependency updates require an explicit lockfile review. Host-specific memory/analyzer changes are separate from toolchain version changes.

Credentials, signing keys, build outputs and local configuration are excluded from Git. Do not commit the local MapKit key.

## Hosted test environment

The existing hosted test server is `https://api.momiq.net/api`; it is not a production-ready customer launch. New environment-guarded builds must use a separate staging endpoint for hosted test login. SMS integration and production signing are deferred to the final phase.

For localhost use `flutter run --dart-define=MOMIQ_API_URL=http://127.0.0.1:8080/api` and USB adb reverse. Run local live integration tests with the same URL override. GitHub Actions runs analysis and tests on pushes/PRs; mobile store releases/signing are not configured.

## Data availability

The backend sitter catalog starts empty. Listings and profiles are revisioned server data. Local/test moderation publishes explicitly marked test listings; this is not MyID verification. Discovery pages filter current calendar/capacity, prices, cat/dog and favorites on the server. Approximate GPS points enable server proximity order; browsing without GPS uses the Toshkent catalog. The exact city boundary remains a release gate. Bookings, commission debits/refunds, two-party care confirmations, daily care entries, immutable completed-booking reviews and administrator-reviewed disputes use server responses. Native and physical-device gaps remain in the checklist, particularly the blocked M055 test and real iPhone checks. Login code `111111` is confined to explicitly enabled test environments; hosted production activation remains closed.

## Manual wallet payment drafts

Opening a payment QR first persists its version, recipient and instructions on this device. New receipt submissions require the payment time or transaction ID shown by the provider. The user supplies these as evidence; they do not pre-fill the admin's verified transfer ID. Amount, receipt and stable retry ID are saved in an AES-256-GCM authenticated file in the app support directory. A device-only secure-storage key and account/API URL binding isolate drafts. If a write fails the initial QR remains hidden; subsequent save failures are shown with a retry action. Corrupt drafts are preserved until explicitly discarded. Consent must be reconfirmed after reopening.

A successful server response clears the draft. A lost response preserves the same request ID for a safe retry; the server credits nothing until an admin verifies actual incoming funds. Explicit signing out or confirmed local-session cleanup removes the encrypted files and key. A build/environment mismatch alone preserves them. Drafts do not survive uninstall, logout or device loss; the original provider receipt remains the recovery evidence. No real payment should be made through local TEST QR images.

Rejected requests and requests needing clarification open an amendment form with their original QR/evidence revision. It explicitly asks the sitter not to pay again. Amendment drafts have separate encrypted storage from new-payment drafts. The original QR, stable retry ID and renewed consent are preserved across restart. Stale form revisions cannot change current evidence. Request history loads older snapshots and images on demand. A successful server submission followed by local cleanup failure offers cleanup retry without posting a second request.

## Session lifecycle

The profile tab can switch customer/sitter mode without logout. Server enrollment is limited to the same account's two self-service roles; it grants no listing approval, MyID verification or admin access. The app waits for success, resets old route stores and restores the selected role after restart while keeping the token and encrypted payment drafts. Incomplete registration reopens with saved profile fields. Unsaved keystroke recovery remains M124.

The customer and sitter bell buttons open server-backed notification history. Wallet and listing review events paginate, retain read state and open only known local wallet/listing destinations. Existing decisions before migration 6 have no retroactive notice. External push and booking/chat/care notifications remain unfinished; optional order/chat/care preferences do not hide transactional wallet/moderation history.

OTP login returns the existing server account. Completed profiles go straight to the selected role home; incomplete profiles resume registration. The token, selected role and last account snapshot persist across app restarts. Startup validates the session with `/api/me`; network failures keep the saved login, while expired/blocked sessions return to role selection.

Logout revokes the current session when the server is reachable and clears this device's account/session caches, pets, sitter drafts and copied care videos. The server account remains intact. Offline logout still clears the device; the unreachable server session expires normally. Other devices' sessions are unaffected. Sitter registration data is saved to the account, but publishing a sitter listing remains separate.


Payment QR media: the original draft QR can be enlarged or explicitly saved to the system gallery with `gal` 2.3.3. Only the operator QR is exported; private receipts stay in the encrypted draft and authenticated API. Saved QR files remain outside the app after logout, so the screen instructs users to fetch the current QR before each new payment. Gallery permission denial/storage failure never reports success. Receipt selection offers camera/gallery, requests no full metadata, and validates PNG/JPEG/WebP size, dimensions and decoding before replacing the previous evidence. iOS add-only photo permission and Android legacy write permission (API <=29 only) are declared. Before launching the external picker, an encrypted interruption marker preserves the prior evidence. If the process dies, the wallet requires explicit reselection before submission; cancellation does not bypass that requirement. Global lost-picker data is never automatically attached across profile/pet/payment flows. Native process-death verification and physical iPhone permission/media checks remain open in M139.


## Participant chat

Customer and sitter chat tabs use the same authenticated conversation inbox. A listing contact button creates a server-validated conversation. Only participants can read/write; admin support history is labelled separately. History pages use server sequence cursors, images load on demand, and the peer read marker controls the Read label. Sent means accepted by the server, not delivered to a device.

Active chat polls only deltas every five seconds and inbox metadata every ten seconds. Background or covered routes stop polling; switching tabs disposes their timer. The former global three-second account/full-message poll was removed. Before POST, the exact message and random request ID are saved with the existing AES-GCM storage implementation under a separate account/API/conversation scope. Failed response or restart locks that request for exact retry. The same logout cleanup removes these encrypted outboxes. Typing and image selection before Send remain in memory; this limitation must be kept visible in release review. New sent messages never advance the incoming cursor, so a concurrently received message cannot be skipped.

Local API/widget tests cover ownership, retry/restart, concurrent send, pagination, read markers and lifecycle. Android emulator evidence is recorded in the backend checklist; physical Android/iPhone acceptance is a separate release gate. Booking linkage is implemented. External push and full operator role separation remain unfinished.


Chat safety controls: each incoming message can be reported with a reason; the chat menu offers pair-wide block/unblock and own report history. Reporting does not automatically block. Moderator redactions arrive on a separate change cursor, including changes to already-loaded messages; a stale response cannot restore hidden content. A pending outbox can be explicitly cleared after a warning that this is not a recall. Admin decisions and evidence access are audited. Native chat/media verification and dedicated moderator permissions remain release gates.


Authenticated pet management supports archive/restore with account revisions, an archive list and active-only booking selection. Failed requests do not hide a pet optimistically. Remote records survive account/store reload; unauthenticated preview pets remain session-only. Old booking metadata is retained by server snapshots. Local/test `bookingEnabled=true` listings open the server-quote flow. Both roles have paginated booking lists/details and revisioned encrypted retry commands. Price and commission come from the immutable quote. Started-24-hour pricing and fixed daily home-visit fees follow the approved policy. Two-party start/end, no-show disputes and in-app booking reminders are implemented; native completion verification, external push and public production rollout remain open.

## Booking communication and notices

Local/test booking details open the existing customer/sitter/service conversation for either participant. The chat menu lists only bookings shared in that service, with pagination and server-side access checks. Low sitter balance does not interrupt an existing agreement's chat. A closed request that was never accepted cannot create new contact.

Committed booking status changes appear in the in-app notification list and open the exact booking after its server ID is validated. External push/SMS is not yet connected. The local/test server now expires unanswered requests in the background; the app does not have to remain open. See the backend checklist for lifecycle and release gates.

Local/test booking details also support separate start and completion confirmations from each participant. One confirmation waits for the other party; only both confirmations activate or complete care. Start is limited to the agreed interval, early completion keeps the agreed price, and these actions never debit another commission. Pending commands survive restart in the encrypted booking outbox. Native two-party acceptance remains a checklist verification item; isolated HTTP and widget tests cover the transitions.


## Daily video reports

Booking care opens the server-backed daily video list. Server windows are 07:00–11:00 and 18:00–22:00 Asia/Tashkent; a video must be 10–60 seconds, at most 32 MiB, H.264/HEVC MP4/MOV at 1080p or below. The assigned active sitter selects/captures, saves an encrypted account/API/booking-scoped outbox and sends with progress, cancellation and exact-ID retry. Upload completion is shown only after server confirmation. Participants reopen dates, view authenticated posters and play authenticated byte-range H.264/AAC derivatives using video_player 2.14.1. Backgrounding pauses playback; changing sessions invalidates the controller and outbox actions.

Video files are normalized by the server, not FFmpeg in the APK. A cancelled transfer may already have committed: refresh/retry checks server state; clearing a local draft does not remove a server report. Picker recovery after Android process death uses an encrypted target marker and explicit re-selection; actual native process-death acceptance, device codec/playback and iOS camera permissions remain checklist gates. Original encrypted video drafts can use up to 46 MiB of encoded storage; peak memory/performance needs device profiling (M131). The existing receipt-draft limit remains 10 MiB.


Video retention is now server-enforced: 30 days after the booking ends and any dispute resolution; ongoing disputes hold the report. Expired items remain in history without a player or thumbnail request. Video drafts have a separate encrypted namespace and are removed after 30 days using timestamps supplied by the server on refresh; wallet receipt evidence is unaffected. Logout clears both namespaces. Disposable picker copies inside the app temp directory are removed only after the encrypted draft is flushed; gallery originals outside that directory are preserved. OS-held/process-interrupted caches remain part of device/crash acceptance, not a claim of remotely erasing an offline phone.


CI note (2026-10-28): the macOS ARM64 job for 2ff8e3a never acquired a hosted runner; GitHub reported capacity constraints before any step ran. The simulator job now uses the supported `macos-15-intel` label. This changes CI host architecture, not the iOS release target, and does not replace ARM64 device/signing QA. Runner source: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job .

Video deadlines also appear in in-app care notifications: sitter reminder 30 minutes before closure, missing-video notice to both parties after closure. The sitter may submit one immutable reason/emergency statement per missing pet/slot; an encrypted explanation draft supports exact retry without changing the video draft. Participants can open booking-linked private support from the video page. Reasons are sitter statements, not verification or video replacement. There is no automatic fine/refund. External device push is still a separate release gate.

For the running 8081 Android emulator preview, use `./tool/build-preview.ps1 -Port 8081`. It checks local instance health, writes a matching private build config, and records APK SHA-256/API/instance in `.local/preview-apk.json` after a successful build. Wait for completion and verify that manifest before installation. `config/local.json` targets 8080; changing the API origin blocks reuse and preserves local credentials/drafts. The recovery screen offers retry or explicitly confirmed destructive cleanup; it never displays the old cached account or transmits its token to the new origin. Server accounts remain unchanged. This prevents future accidental draft loss; it cannot recover previously erased drafts.

Manual care-address search/map selection no longer depends on GPS or OS location permission. No permission prompt appears when entering the sitter service form. Only the explicit current-location action asks for location access; denial/disabled GPS keeps manual selection available and offers settings/retry. A fix with accuracy worse than 100 m, invalid coordinates or a timestamp older than five minutes/more than one minute in the future is rejected. Android fused-provider timeout still retries the native provider, bounded at 20 + 25 seconds. Customer discovery remains available through the Toshkent catalog when location is unavailable. MapKit key/provider and physical-device acceptance remain separate gates.


Top-up corrections appear as negative source-linked history with a reason and timestamp. The sitter can open the original receipt history and page through corrections; no correction mutation is available in the app. They correct an erroneous approved credit and do not refund money to a card.
