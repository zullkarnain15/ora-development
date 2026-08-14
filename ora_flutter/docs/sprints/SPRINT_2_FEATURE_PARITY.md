# Sprint 2 Execution Brief - Home, Quest, Guild, Leaderboard, Profile, and Activity Foundation

Status: **ready after Sprint 1 acceptance**  
Project: `D:\ORA-Development\ora_flutter`  
Behavior reference: `D:\ORA-Development\ORA`  
Architecture reference: `docs/ANDROID_TO_FLUTTER_MIGRATION_ANALYSIS.md`

## Objective

Deliver the complete non-tracking ORA experience using the current Apps Script contracts: Home, user stats, Quest progress and claims, Guild, leaderboard, Profile, Settings, and the local final-activity/history foundation.

This Sprint must remain independently testable without a live GPS stream.

## Preconditions

- Sprint 1 session gate, API client, app shell, and theme are accepted.
- Contract fixtures contain no real session token, NIK, or personal data.
- Any dependency proposal is reviewed before `pubspec.yaml` changes.

## Locked rules

- Backend totals/XP/level are authoritative; do not derive account XP from unsynced local activities.
- Quest/Guild/leaderboard rules remain backend-owned.
- Preserve owner isolation for every local query.
- Preserve current loading/error/empty semantics.
- Do not add tracking, native location bridges, or route viewing.
- Keep Guild members, leaderboard, and Guild directory as distinct sub-views.

## Deliverables

### 1. API repositories and controllers

- User Stats repository/controller.
- Quest master/progress/claim repository/controller.
- Guild summary and Guild directory repository/controller.
- Leaderboard repository/controller for GLOBAL/GUILD and XP/distance/runs.
- Contract fixture coverage for all 13 Apps Script actions.
- Consistent normalized failures without hiding `UNAUTHORIZED`/`SESSION_EXPIRED` from the SessionController.

### 2. Home and user stats

- OTO branding, welcome identity, Adventurer Card, level, total XP, and progress.
- Preserve current XP progress display behavior until a separately approved rule changes it.
- Latest local adventure and sync-status entry points.
- Loading, unavailable, empty, and retry states.

### 3. Quest

- Refresh on entry.
- Preserve current fallback from authenticated progress to public Quest master, but show that data as fallback/stale rather than silently presenting it as complete progress.
- Preserve Quest visual states: not started, in progress, complete/claimable, claimed, no Guild, unsupported Guild reward, unknown type.
- Prevent concurrent claims.
- Refresh user stats after a successful claim.

### 4. Guild and leaderboard

- Guild summary, member totals, active member list, and unassigned/inactive states.
- Guild directory with current-Guild highlight and legacy metadata fallback behavior.
- Leaderboard scope/metric selectors, current-user rank, top rows, empty board, and `NO_GUILD` state.
- Keep the dense RPG presentation readable under text scaling.

### 5. Profile and Settings

- Identity, Guild, level/XP, backend totals, Adventure Log, per-activity pending/synced status.
- Settings account, run/data safety information, About, back, and logout.
- Do not add nickname rename UI.

### 6. Local activity foundation

- Define `FinalActivity`, owner-scoped repository, and storage schema versioning.
- Preserve Android `ActivityEntity` fields and PENDING/SYNCED semantics.
- Implement owner-scoped latest, newest-first list, count, distance, and active-duration totals.
- Add primary-key duplicate behavior.
- Add an upgrade/migration fixture representing Android `ora.db` version 1.
- Reserve clean interfaces for RunSession, LocationPoint, RunEvent, and SyncQueue, but do not implement tracking behavior in this Sprint.

## Required tests

- All 13 API action response/error fixtures.
- User stats parsing, default stats, and owner mismatch.
- Quest fallback, progress states, claim blocking, claim success, and Guild reward block.
- Guild unassigned/inactive/legacy resolution fixtures.
- Leaderboard scope/metric forwarding, tie order, top-50/current rank, and empty/no-Guild states.
- Activity owner isolation, ordering, aggregates, duplicate key, pending/synced display.
- Widget tests for loading/error/empty content at supported text scales.

## Acceptance criteria

- Every non-Run destination contains the real ORA feature UI, not demo content.
- Live or fixture responses render the same fields/status semantics as Android.
- Quest claim is single-flight and refreshes stats after success.
- No local activity from another NIK is visible or uploaded.
- App remains usable in a controlled offline/error state.
- `flutter analyze`, tests, and Android debug build pass.
- iOS build/configuration is validated on a Mac.
- No GPS/native tracking behavior is introduced.

## Verification commands

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

## Stop condition

Stop after the Sprint 2 acceptance report. Do not begin native tracking until Sprint 3 and its bridge/storage decisions are explicitly approved.
