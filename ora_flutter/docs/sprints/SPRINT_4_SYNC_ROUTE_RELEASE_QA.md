# Sprint 4 Execution Brief - Durable Sync, Route Viewer, Integration, and Release QA

Status: **ready after Sprint 3 and the duration release blocker are accepted**  
Project: `D:\ORA-Development\ora_flutter`  
Behavior reference: `D:\ORA-Development\ORA`  
Architecture reference: `docs/ANDROID_TO_FLUTTER_MIGRATION_ANALYSIS.md`

## Objective

Complete finalized-activity synchronization, pure Flutter route display, cross-feature integration, field calibration, and Android/iOS release hardening.

Sprint 4 must re-run the duration regression matrix. It must not reopen timer semantics casually or mask a device-specific failure with a UI workaround.

## Preconditions

- Sprint 3 offline run, finalization, persistence, recovery, and native adapters are accepted.
- Duration bug has a documented root cause, fix, and regression tests.
- Backend compatibility change for truthful Android/iOS activity source is explicitly approved before backend implementation.

## Locked rules

- Backend/network remains outside the GPS critical path.
- Stable activity/session ID is reused for every retry.
- SAVED and DUPLICATE are terminal server acknowledgements.
- A local finalized activity is never deleted because sync failed.
- Route viewer reads accepted points and never calculates or mutates tracking distance.
- No Google Maps, MapLibre, OSM basemap, map matching, or live GPS upload.
- TrackingPolicy changes require field evidence and regression fixtures.

## Deliverables

### 1. Durable activity sync

- Versioned payload mapper preserving the existing Apps Script fields.
- Durable SyncQueue with state, retryCount, lastAttemptAt, nextAttemptAt/backoff, payload version, and server ACK/status.
- Startup, post-finalization, manual, and network-restored triggers with single-flight protection.
- Persist ACK before marking an activity SYNCED.
- Owner/session isolation for every upload.
- Central SessionController handling for expired/unauthorized sync.
- Backward-compatible backend support for truthful `ANDROID`/`IOS` source only after approval.
- Preserve server XP calculation and `(NIK, ActivityId)` duplicate rule.

### 2. Pure Flutter route viewer

- Load accepted points for a finalized activity.
- Fit route to canvas with padding and preserved aspect ratio.
- Draw route line, Start marker, Finish marker, and ORA pixel/RPG frame using `CustomPainter`.
- Optional display-only simplification for large point sets.
- Preserve original accepted points and final distance.
- Handle empty, one-point, duplicate-coordinate, vertical, horizontal, and very long routes safely.

### 3. Product integration

- Finalized offline activity appears immediately on Home/Profile.
- Pending/synced status updates durably.
- Successful sync refreshes user stats and Quest progress without blocking run storage.
- Logout during an active/recoverable run uses an approved safe flow; no silent discard or ownership transfer.
- Summary, history, route, sync, recovery, and user ownership use the same stable IDs.

### 4. Duration regression and field QA

Re-run Sprint 3 device coverage with production-like builds:

- older working Android device;
- Android 12/13 precise and approximate flows;
- Android 14/15 foreground-service restrictions;
- current/new-generation physical Android device;
- at least two vendors;
- representative iPhone foreground/background/lock flow.

For each device verify:

- acquisition status is explicit;
- RUNNING active duration advances without depending on location callback frequency;
- delayed UI ticks catch up;
- pause freezes active duration;
- resume starts only after reacquisition;
- screen lock/background preserves duration when platform rules permit;
- process recovery does not reset or double-count duration;
- final payload duration equals the accepted active-duration rule.

### 5. Full route/tracking field matrix

- Open-sky straight route.
- Known-distance loop/stadium.
- Urban canyon/high buildings.
- Short tunnel/underpass.
- Stationary 2-3 minutes.
- Pause then move 200-300 m.
- Poor GPS start.
- Internet disabled for the whole run.
- App/process interruption and recovery.
- Lock screen Android and iOS.
- Low battery and power saver.

Record policy version, accepted/rejected counts by reason, accuracy distribution, maximum gap, recovery count, test-only raw-versus-accepted distance, battery delta, duration drift, model/API/vendor, and result.

### 6. Release hardening

- Android/iOS permission copy and store declarations.
- Data retention/privacy review for GPS evidence, diagnostics, and session token.
- Performance, memory, battery, text scaling, and screen-reader review.
- Signed Android readiness and iOS signing/TestFlight readiness.
- Cleanup only items explicitly approved after parity review.

## Required tests

- Sync SAVED, DUPLICATE, error, timeout, invalid response, and session expiry.
- Queue restart/backoff/single-flight and cross-owner rejection.
- Retry creates no duplicate server row or XP.
- Offline finish -> pending -> reconnect -> synced -> stats/Quest refresh.
- Route painter never modifies points or distance.
- Route bounds/markers for edge cases and large point sets.
- Logout/relogin and recovery owner isolation.
- Full duration matrix from Sprint 3.
- Full Android/iOS field-test matrix with documented pass/fail evidence.

## Acceptance criteria

- Repeated retry of one activity never duplicates backend activity or XP.
- Offline finish always produces a visible local activity and durable pending queue item.
- SYNCED is shown only after durable acknowledgement.
- Route renders with Start/Finish and no map dependency.
- No catastrophic GPS spike occurs in normal scenarios.
- Pause boundary and recovery duplication tests pass 100%.
- Duration passes on both older and newer Android devices and remains correct across lock/background/recovery.
- Android and iOS exhibit functionally equivalent start/pause/resume/end/offline/recovery behavior within platform rules.
- Release builds and store/privacy/signing checklists are complete.

## Verification commands

```powershell
flutter analyze
flutter test
flutter build apk --release
```

On macOS:

```bash
flutter test
flutter build ios --release --no-codesign
```

## Stop condition

Do not declare production readiness when the duration matrix, sync idempotency evidence, physical-device background tests, or iOS build gate is missing.
