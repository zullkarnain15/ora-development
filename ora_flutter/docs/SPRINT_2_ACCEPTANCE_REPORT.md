# Sprint 2 Acceptance Report

Date: 2026-08-14  
Project: `D:\ORA-Development\ora_flutter`  
Status: **Android implementation accepted; iOS statically validated and pending the final macOS build**

## Delivered

- Real Home with backend-authoritative level, XP, totals, progress, latest local adventure, refresh, and sync entry point.
- Real Quest board with authenticated progress, clearly labelled public-master fallback, all Android visual states, single-flight claims, Guild reward blocking, and stats refresh after a claim.
- Real Guild Hall with distinct Members, Leaderboard, and Guild Directory views; unassigned/inactive/legacy states; GLOBAL/GUILD and XP/distance/runs selectors; current-user rank and empty states.
- Real Profile with identity, Guild, level/XP, backend totals, owner-scoped Adventure Log, and PENDING/SYNCED display.
- Expanded Settings with account, run-safety, data-safety, About, back, and logout. Nickname rename remains unavailable.
- Apps Script coverage for all 13 contracts: health, config, levels, quests, login, activateNickname, submitActivity, getUserStats, getGuildSummary, getGuildDirectory, getLeaderboard, getQuestProgress, and claimQuestReward.
- Explicit POST 302 redirect handling required by the live Google Apps Script deployment.
- `FinalActivity`, owner-scoped `ActivityStore`, `ora.db` schema versioning, PENDING/SYNCED workflow, aggregates, duplicate behavior, and an executable Android version-1 migration fixture.
- Reserved repository interfaces for RunSession, LocationPoint, RunEvent, and SyncQueue without implementing tracking.

No GPS, native tracking, route viewer, map, or Sprint 3 behavior was added.

## Dependencies

- Runtime: `sqflite 2.4.3`, `path 1.9.1`.
- Test only: `sqflite_common_ffi 2.4.2`.

See `docs/SPRINT_2_DEPENDENCY_DECISION.md`.

## Verification

| Gate | Result |
|---|---|
| `flutter pub get` | PASS |
| `flutter analyze` | PASS - no issues |
| `flutter test` | PASS - 56 tests |
| Android `flutter build apk --debug` | PASS |
| Live backend GET `health` | PASS - service UP |
| Live backend POST `config` | PASS - successful envelope |
| Android v1 SQLite migration fixture | PASS - data preserved |
| Apps Script POST 302 redirect test | PASS |

APK: `build\app\outputs\flutter-apk\app-debug.apk`  
SHA-256: `9BDD972D6DDBC7F456580C021E86FE2514B844D80A83C13A0969BCBBE697854D`

No Android phone or emulator was connected to this workstation, so physical-device UI/login testing remains a manual smoke gate. No real NIK, PIN, session token, or personal data was committed or logged.

## iOS static validation

- `Info.plist` parses as valid XML.
- Xcode deployment target is iOS 15.0.
- Keychain implementation imports Security and registers `ora/session_store`.
- Generated iOS plugin registrant includes `SqflitePlugin` from `sqflite_darwin`.
- Flutter generated package declares iOS 15.0.
- No iOS location permission or tracking capability was introduced in Sprint 2.

The following remains deferred until a Mac is available and must not be reported as executed yet:

```bash
flutter build ios --debug --no-codesign
```

## Stop

Sprint 3 has not been started. Native tracking and the duration bug remain isolated to the Sprint 3 execution brief.
