# Sprint 1 Acceptance Report

Date: 2026-08-14  
Project: `D:\ORA-Development\ora_flutter`  
Status: **implementation complete; final acceptance pending macOS iOS build gate**

## Delivered

- Replaced the Flutter counter template with ORA bootstrap, root error handling, session gate, and authenticated shell.
- Added the forest/gold ORA theme, Press Start 2P font, 25 approved Android image assets, reusable card/title/icon/badge/stat/status widgets, safe areas, semantics, and scalable readable text.
- Added five shell destinations: Home, Quest, emphasized Run, Guild, and You. Out-of-sprint destinations are explicit placeholders only.
- Added Settings as a nested authenticated route without bottom navigation. Logout clears the authenticated route stack and session.
- Added Apps Script client using `dart:io`/`dart:convert`, 15-second connect and 20-second read timeouts, nested and flat success envelopes, normalized response/network failures, and centralized `UNAUTHORIZED`/`SESSION_EXPIRED` handling.
- Added login, first-time nickname activation, exact PIN/nickname rules, canonical uppercase nickname submission, session restore/expiry, and logout.
- Added `SessionStore` with Android Keystore + AES-GCM and iOS Keychain native implementations. See `docs/SPRINT_1_DEPENDENCY_DECISION.md`.
- Added Android Internet permission, disabled Android backup, matched the Android reference minimum SDK 26, and set host display name to ORA.

No Quest, Guild, tracking, activity sync, or route drawing behavior was implemented.

## Automated verification

| Gate | Result |
|---|---|
| `flutter pub get` | PASS |
| `flutter analyze` | PASS - no issues |
| `flutter test` | PASS - 36 tests |
| `flutter build apk --debug` | PASS |
| Android secure-storage native compilation | PASS as part of APK build |
| Flutter demo-content audit | PASS - no visible counter/demo implementation remains |

The tests cover all required validation boundaries, login/activation outcomes, API envelope/error/timeout fixtures, session restore/expiry/logout, centralized expiry routing, keyboard submission, loading/error states, shell navigation, Settings isolation, and logout route cleanup.

## Pending acceptance gates

The following cannot be executed on this Windows workstation:

```bash
flutter build ios --debug --no-codesign
```

Run that command on macOS with Xcode before marking Sprint 1 fully accepted. A live login/activation smoke test also requires approved test credentials and was not attempted; no real token or PIN was committed or logged.

## Reference safety

All writes were limited to `D:\ORA-Development\ora_flutter`. The Android reference at `D:\ORA-Development\ORA` was used read-only as the behavior and asset source. It is not a Git repository, so a Git cleanliness proof is unavailable.

## Stop

Sprint 2 has not been started. Begin it only after explicit approval.
