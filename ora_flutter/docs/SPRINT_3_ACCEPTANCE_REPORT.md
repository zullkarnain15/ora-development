# Sprint 3 Acceptance Report

Date: 2026-08-14  
Project: `D:\ORA-Development\ora_flutter`  
Status: **implementation complete; release acceptance blocked by the remaining physical-device matrix and macOS/iPhone gates**

## Delivered

- Pure-Dart tracking domain with explicit `IDLE`, `START_REQUESTED`, `ACQUIRING_GPS`, `RUNNING`, `PAUSED`, `REACQUIRING`, `FINALIZING`, `FINISHED`, and `RECOVERABLE_SESSION` states.
- Three separate time semantics:
  - session elapsed from START to END;
  - active duration only while quality-ready `RUNNING`;
  - provider fix age/order from the native monotonic clock.
- Active duration derived from a monotonic anchor. It advances without one GPS callback per second and catches up after delayed UI ticks or lifecycle suspension.
- Versioned GPS policy. Android parity V1 preserves the 30 m accuracy, 2 m segment, 5 m jitter, 12 m/s speed, 15 second freshness, 10 second re-entry, and 20 m pace thresholds. V2 adds continuity confirmation after an implausible jump without weakening those thresholds.
- Coordinate, freshness, order, accuracy, duplicate, jitter, implied-speed, continuity, long-gap, and pause-boundary gates.
- `ora.db` schema version 3 with `run_sessions`, `location_points`, `run_events`, and `sync_queue`, while preserving Android/Flutter activity data.
- Transactional point decision plus critical run counters, persisted monotonic anchors/checkpoints, final distance reconciliation from accepted segments, idempotent finalization, and one `FinalActivity` per run.
- Startup recovery with Resume & Reacquire, End & Save, and confirmed Discard. Recovery never joins pre-interruption and post-reacquisition GPS segments.
- Versioned Android/iOS MethodChannel and EventChannel contract (`v1`).
- Android location foreground service started from a visible user action, declared with `foregroundServiceType="location"`, precise/approximate distinction, provider checks, a privacy-safe debug timeline, ongoing notification, and pause/resume/finish notification actions.
- Android native heartbeat/checkpoint evidence so process recovery can bound active time to a live foreground service rather than wall-clock guesses.
- iOS Core Location adapter behind the same normalized contract, with precise-location handling, fitness accuracy, 2 m distance filter, Background Modes location configuration, and immediate stop on END.
- Complete Run UI for acquisition, running, pause, reacquisition, finalization, recovery, GPS quality, distance, active duration, pace, background state, and actionable errors.
- Serialized controller commands so rapid pause/resume/finish inputs cannot leave a stale native command authoritative after FINISH.

## Duration bug finding and fix

The Android reference starts `activeStartedAtMillis` only after the first accepted GPS `BASELINE`. Therefore a device that receives no callback, approximate-only location, disabled provider, service-start failure, or only fixes worse than 30 m remains in acquisition with active duration at zero.

The physical API 36 test bounded the observed failure further:

- precise foreground permission was granted;
- Android allowed the user-visible location foreground service;
- the service was promoted with type `location` and an ongoing notification;
- location callbacks reached the Flutter controller;
- the available indoor fix was classified `POOR` (>30 m), so no baseline was accepted;
- ORA displayed acquisition/reacquisition and an actionable low-accuracy message instead of claiming that the run was active.

The new clock engine fixes the timing layer after the quality-ready transition: a callback changes the state to `RUNNING` once, then active duration is recomputed from the persisted monotonic anchor. Regression coverage proves it advances with no further GPS callback, catches up after delayed UI sampling, includes legitimate lock/deep-sleep time, freezes on pause, and does not reuse monotonic values across a reboot.

The original report across all “new-generation phones” is not declared closed yet. The API 36 indoor result did not reach an actual precise baseline, and the required older/API 31-35/vendor comparison is still incomplete.

## Verification

| Gate | Result |
|---|---|
| `flutter analyze` | PASS - no issues |
| `flutter test` | PASS - 83 tests |
| Android `flutter build apk --debug` | PASS |
| Android `lintDebug` | PASS |
| Android manifest/APK inspection | PASS - min API 26, target API 36, location FGS type and required permissions present |
| Android v1 database migration to v3 | PASS - activity preserved and tracking tables created |
| Idempotent finalization | PASS - repeated finalization produces one activity |
| Rejected/raw point distance | PASS - contributes zero |
| Physical install/start on Samsung API 36 | PASS |
| Physical API 36 foreground service and notification | PASS |
| Physical API 36 accepted outdoor baseline and advancing duration | NOT RUN - indoor fix remained `POOR` |
| Android API 26-35 and second-vendor matrix | NOT RUN |
| iOS static configuration | PASS |
| iOS compile and physical smoke test | DEFERRED - macOS/Xcode/iPhone unavailable |

APK: `build\app\outputs\flutter-apk\app-debug.apk`  
Size: `192391227` bytes  
SHA-256: `3E95633562B3E1B2F326860BE9007AF60D3D7D6CA4C6CE00F746954E708A82CD`

## Physical test side effect

The API 36 smoke test finalized one pending local test activity at approximately 15:38 with `0.00 KM`, `00:00`, and no pace. It is visible as the latest adventure and must not be treated as a real run or synced. It was not removed by direct database surgery because modifying the live SQLite/WAL files outside the application would put existing user data at risk.

## iOS static result and limitation

- `Info.plist` parses as XML and contains both location usage descriptions plus `UIBackgroundModes = location`.
- Xcode deployment target remains iOS 15.0 and Swift version 5.0.
- Core Location registers the same v1 method/event channels, uses monotonic system uptime, configures best accuracy and a 2 m distance filter, supports pause/resume, and stops immediately on END.
- A user force-quit is an OS boundary: ORA cannot promise continuous standard Core Location delivery after force-quit. The persisted run is offered for safe recovery on the next manual launch.

The iOS source has not been compiled on Windows. Run this on macOS before acceptance:

```bash
flutter build ios --debug --no-codesign
```

Then perform foreground, background, lock-screen, pause/resume, process interruption, and recovery smoke tests on an iPhone.

## Stop condition

Do not begin Sprint 4 yet. Sprint 3 remains a release blocker until the device rows in `docs/SPRINT_3_DEVICE_TEST_MATRIX.md` are completed, including an accepted outdoor baseline with advancing duration on the reported newer phone, an older Android comparison, API 31-35 coverage, and a second Android vendor, or until the user explicitly waives those gates.
