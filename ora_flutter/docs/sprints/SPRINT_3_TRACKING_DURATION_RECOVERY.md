# Sprint 3 Execution Brief - Tracking Engine, Duration Bug, Native Adapters, and Recovery

Status: **ready after Sprint 2 acceptance and native/storage design approval**  
Project: `D:\ORA-Development\ora_flutter`  
Behavior reference: `D:\ORA-Development\ORA`  
Architecture reference: `docs/ANDROID_TO_FLUTTER_MIGRATION_ANALYSIS.md`

## Objective

Build an offline-first Tracking Engine for Android and iOS, including persisted run state, GPS point validation, pause/resume, finalization, and crash recovery.

This Sprint also owns the reported bug:

> Duration runs on older phones but does not run on newer-generation phones.

The bug is a release blocker. It must be reproduced, instrumented, explained, fixed, and protected by regression tests. Do not hide it by loosening GPS thresholds or starting an unrelated timer.

## Known evidence and careful working hypothesis

In the Android reference, `activeStartedAtMillis` is initially zero and `startTimer()` is called only after `RunLocationEngine` returns the first `BASELINE`. Therefore the displayed active duration intentionally stays at zero while state is `ACQUIRING GPS`.

If a newer device never reaches an accepted baseline, duration appears frozen. Possible causes that must be distinguished rather than assumed:

- approximate rather than precise location on Android 12+;
- all fixes rejected because accuracy remains above 30 m;
- provider disabled or long time-to-first-fix;
- location callback not delivered;
- Android 12+ foreground-service start restrictions;
- Android 14+ while-in-use location/foreground-service permission enforcement;
- battery saver/vendor background behavior;
- process/service restart or state loss;
- UI ticker suspension even though the monotonic time basis remains correct.

The Android code correctly compares `Location.elapsedRealtimeNanos` with `SystemClock.elapsedRealtimeNanos`; both are monotonic within one boot. The migration must retain a monotonic clock for interval calculations and must not use wall-clock time for duration deltas.

Official references to use during implementation:

- [Android foreground-service launch restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Android foreground-service launch flow](https://developer.android.com/develop/background-work/services/fgs/launch)
- [Android location foreground-service types](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Android runtime location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime)
- [Android SystemClock](https://developer.android.com/reference/android/os/SystemClock)
- [Android Location elapsed realtime](https://developer.android.com/reference/android/location/Location#getElapsedRealtimeNanos())

## Locked clock semantics

Implement and name three separate clocks:

1. **Session elapsed time:** wall interval from START request to END, including acquisition and pause. Persist start/end epoch for presentation/audit and use a monotonic anchor for live interval calculation.
2. **Active duration:** time in the accepted RUNNING state, excluding PAUSED and excluding acquisition/reacquisition until the quality-ready transition. This remains the pace and existing backend `durationSec` basis unless the product explicitly approves a different rule.
3. **GPS fix age/order:** monotonic provider timestamp compared with the local monotonic clock. Never derive this from the UI timer or epoch clock.

The active duration must not advance because a location callback arrives. A callback only causes the state transition into RUNNING. Once RUNNING, duration is derived from persisted monotonic anchors and must remain correct across delayed UI ticks, lock screen, and lifecycle resume.

## Mandatory duration-bug workstream

### 1. Reproduction matrix

Record actual OS information rather than only “old/new phone”:

| Band | Minimum coverage |
|---|---|
| API 26-30 | At least one older Android device/emulator matching the currently working behavior. |
| API 31-33 | Android 12/13 with Precise, Approximate, Only this time, and denied permissions. |
| API 34-35 | Android 14/15 foreground-service and while-in-use restrictions. |
| API 36+ | At least one current/new-generation physical device when available. |
| Vendor coverage | At least two Android vendors, including any vendor/model that reproduces the bug. |

For every run record model, manufacturer, API level, target SDK, security patch, location setting, precise/approximate grant, notification grant, battery saver, vendor optimization, app foreground/background state, and whether the screen is locked.

### 2. Diagnostic event timeline

Capture a privacy-safe timeline with no raw coordinates in ordinary logs:

- START button timestamp and app visibility.
- Permission results and precise/approximate state.
- Foreground-service request, service `onCreate`, foreground promotion, and error.
- Provider enabled/settings result.
- Location-request success/failure.
- First raw callback latency.
- Each pre-baseline decision: age, accuracy class, rejection reason, without coordinates.
- ACQUIRING -> RUNNING transition.
- `activeStartedMonotonic`, accumulated active duration, UI sample time, and rendered duration.
- Pause/resume/reacquire/end transitions.
- Process/service lifecycle interruption.

Diagnostics must be gated for debug/field-test builds and disabled or minimized in production.

### 3. Root-cause decision tree

- No foreground service: verify visible-activity start, permissions, service type, and promotion timing.
- Service active but no raw location: verify provider/settings/request result and vendor/battery behavior.
- Raw location exists but no baseline: report rejection distribution and precise/accuracy state; do not silently weaken policy.
- RUNNING reached but duration remains zero: inspect monotonic anchors, persistence, controller recomputation, and UI sampling.
- Duration advances foreground but fails after lock/background: verify native service continuity and recompute from monotonic anchors rather than Timer tick counts.
- Restart resets duration: recover persisted active segments/events; never reuse monotonic values across a device reboot without an epoch/recovery boundary.

### 4. Required fix characteristics

- Fix the identified layer only: permission/service/provider, state transition, clock engine, persistence, or UI sampling.
- The UI may display a separate “GPS acquisition elapsed” diagnostic/status, but must not label acquisition time as active run duration.
- Once RUNNING, displayed active duration must advance on old and new devices without requiring another GPS point every second.
- A delayed/suspended UI ticker must catch up from the monotonic source when it resumes.
- Pause freezes active duration; resume adds only post-reacquisition RUNNING time.
- Lock screen/deep sleep must not lose interval time while the foreground tracking task is legitimately active.
- Process interruption must restore from persisted events/anchors without double counting.
- Add regression fixtures before tuning any GPS threshold.

## Tracking Engine deliverables

### 1. Pure Dart domain

- RawLocationSample, AcceptedPoint, quality class, decision, reject reason.
- Versioned TrackingPolicy containing all thresholds.
- Current Android policy preserved as a parity fixture.
- Coordinate, freshness/order, accuracy, duplicate, displacement/jitter, implied speed/jump, continuity confirmation, long-gap, and pause-boundary gates.
- Geodesic distance engine and pace/time engines.
- State machine: IDLE, START_REQUESTED, ACQUIRING_GPS, RUNNING, PAUSED, REACQUIRING, FINALIZING, FINISHED, RECOVERABLE_SESSION.

### 2. Local persistence and recovery

- RunSession, LocationPoint, RunEvent, and local SyncQueue records.
- Transactional point decision plus critical session counters.
- Persisted active/elapsed time anchors and accumulated values.
- Final distance reconciliation from accepted points.
- Idempotent finalization producing exactly one FinalActivity.
- Startup recovery: Resume, End & Save, or confirmed Discard.
- Long-gap/restart recovery always reacquires and creates a new anchor.

### 3. Android native adapter

- Versioned MethodChannel/EventChannel contract.
- Start the location foreground service from a user-visible action.
- Declare and validate required foreground-service types and permissions for the target SDK.
- Normalize provider/service/permission errors.
- Ongoing notification with safe pause/resume/finish actions.
- Verify precise versus approximate location and explain remediation.
- Test lock screen, power saver, and vendor battery settings without requesting unnecessary permissions.

### 4. iOS native adapter

- Core Location manager behind the same normalized contract.
- Contextual permission explanation and Background Modes location configuration.
- Appropriate desiredAccuracy/distanceFilter.
- Pause/resume/reacquisition and immediate stop on END.
- Document force-quit limitations and recovery behavior.

### 5. Run UI

- Explicit acquiring/running/paused/reacquiring/finalizing/recovery states.
- Display distance, active duration, pace, GPS quality/status, and background state.
- Do not show “running” when the service/provider failed to start.
- UI update rate may be lower than GPS sample rate, but values must be derived from the controller's source of truth.

## Required tests

- Port every Android RunLocationEngine and pace test.
- Add confirmation-window, quality-band, acquisition, and policy-version fixtures.
- Unit-test session elapsed, active duration, pause accumulation, delayed UI samples, lock/sleep simulation, process restore, and reboot boundary behavior.
- Verify RUNNING duration advances without additional GPS callbacks.
- Verify ACQUIRING duration semantics separately from active duration.
- Finalization twice creates one activity.
- Recovery never joins pre-interruption and post-reacquisition points.
- Native contract/error serialization tests.
- Physical-device duration matrix across the Android API/vendor bands above.
- Physical iPhone foreground, background, lock, pause/resume, and recovery smoke tests.

## Acceptance criteria

- The reported duration bug is reproduced or bounded with evidence, and a root cause is documented.
- On every supported test device, once state becomes RUNNING, active duration advances correctly and is independent from location callback frequency.
- Old phones retain their working behavior.
- New phones do not remain indefinitely in an ambiguous state: the app reaches RUNNING or shows a precise actionable acquisition/service/permission error.
- Pause/resume, lock screen, delayed UI ticks, and recovery do not lose or double-count duration.
- A run completes fully offline and is locally visible.
- No rejected/raw point adds distance.
- Process restart offers safe recovery and never silently discards the run.
- Android and iOS builds/tests pass their platform gates.

## Stop condition

Sprint 3 is not accepted if duration is only tested on an emulator or one Android model. Stop with a device/API evidence table and do not begin Sprint 4 until the duration release blocker is closed or explicitly waived by the user.
