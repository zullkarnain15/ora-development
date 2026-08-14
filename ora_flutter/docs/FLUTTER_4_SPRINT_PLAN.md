# ORA Flutter Migration - Four-Sprint Plan

Status: **proposed only; no Sprint is authorized by this document**  
Companion analysis: `docs/ANDROID_TO_FLUTTER_MIGRATION_ANALYSIS.md`

Execution briefs:

- `docs/sprints/SPRINT_1_FOUNDATION_IDENTITY.md`
- `docs/sprints/SPRINT_2_FEATURE_PARITY.md`
- `docs/sprints/SPRINT_3_TRACKING_DURATION_RECOVERY.md`
- `docs/sprints/SPRINT_4_SYNC_ROUTE_RELEASE_QA.md`

Known release blocker: duration works on older phones but is reported not to advance on newer-generation phones. Sprint 3 owns reproduction, root-cause analysis, correction, and a physical-device/API regression matrix. Sprint 4 must re-run that matrix before release acceptance.

## 1. Delivery principles

- Android business behavior is the parity baseline.
- Blueprint v1.1 is the target architecture and Tracking Engine baseline.
- Each Sprint ends with Android and iOS hosts buildable from the same Flutter codebase.
- A Sprint may add scaffolding needed by later work, but it must not partially implement the later feature's business behavior.
- No map/basemap package, external router, external state-management framework, or location plugin is assumed.
- New dependencies require a written need, alternatives considered, platform impact, and approval.
- Backend contracts stay unchanged unless an explicitly approved compatibility change is listed as a Sprint deliverable.
- Tracking records locally first; network is never in the GPS critical path.

## 2. Definition of Done used by every Sprint

A Sprint is complete only when:

1. `flutter analyze` passes.
2. Flutter unit/widget tests for the Sprint pass.
3. Android debug build passes.
4. iOS build is validated on a Mac for any Sprint that changes shared or iOS code; Windows-only work must at least keep the iOS project/configuration structurally valid and record the pending Mac gate.
5. No previously accepted Sprint behavior regresses.
6. API/storage/native contracts changed in the Sprint have fixtures and version notes.
7. Loading, error, empty, and offline states are exercised where applicable.
8. No Android source-reference file is modified.
9. Documentation is updated for decisions that differ from the analysis.
10. A demonstrable build remains available; no long-lived broken integration branch is accepted.

## 3. Sprint overview

| Sprint | Outcome | Primary independent test |
|---|---|---|
| 1 | App foundation, ORA visual system, navigation, login/activation/session | Login/activation/session fixture flow and app-shell widget tests. |
| 2 | Read-side product parity for Home, Quest, Guild, leaderboard, Profile, Settings, history foundation | Complete API contract fixture suite and feature controller/widget tests without GPS. |
| 3 | Offline-first cross-platform Tracking Engine with local recovery | Pure Dart point/state fixtures plus physical Android/iOS foreground/background/recovery smoke tests. |
| 4 | Durable activity sync, pure Flutter route viewer, integration and field QA | Retry/idempotency tests, route non-mutation tests, and full device field matrix. |

## Sprint 1 - Foundation, Design System, and Identity

### Goal

Create the stable Flutter foundation and reproduce the complete identity gate: ORA theme, assets, navigation shell, login, first-time nickname activation, session persistence/expiry, and logout. No Quest/Guild/Run implementation is included.

### In scope

#### Architecture/bootstrap

- Establish `lib/app`, `lib/core`, `lib/shared`, and feature-first folders.
- Create application bootstrap and root session gate.
- Use Flutter's built-in Navigator and `ChangeNotifier`/`ValueNotifier`/`InheritedWidget` as needed.
- Create normalized `AppFailure`/`BackendError` models.
- Create API client using `dart:io` and `dart:convert` with current 15 s connect and 20 s read behavior or a documented equivalent.
- Decode both standard nested `data` envelopes and existing flat success responses.
- Add contract fixtures for success/error envelopes before feature repositories depend on them.

#### ORA design system

- Import approved current ORA assets and Press Start 2P.
- Implement forest/gold theme tokens and shared `OraCard`, `OraIcon`, `OraScreenTitle`, `PixelBadge`, stat-line, and feature-state widgets.
- Implement scalable typography; avoid copying unreadable 8 sp text as a hard requirement.
- Implement five-tab shell placeholders: Home, Quest, Run, Guild, You.
- Preserve Run destination emphasis and Settings-without-bottom-bar behavior.

#### Auth/session

- Port PIN and nickname validation as tested domain rules.
- Implement login and activation API calls with exact action/payload names.
- Implement Login and Create Adventurer screens with loading/error states.
- Implement session model, 30-day expiry handling, restore, and local logout.
- Route `SESSION_EXPIRED`/`UNAUTHORIZED` through one SessionController.
- Keep nickname rename unavailable because backend does not support it.
- Put token persistence behind a `SessionStore` interface. Decide whether a small native secure-storage bridge is required; do not add a package without approval.
- Preserve backup/data-extraction safeguards on Android and add the iOS equivalent protection decision.

### Explicitly out of scope

- Home data, XP/level, Quest, Guild, leaderboard, activity history.
- GPS permissions, tracking, foreground service, Core Location.
- Local run database and activity sync.
- Route drawing.
- Backend modifications.

### Tests

- PIN: empty, short, long, non-numeric, valid four digits.
- Nickname: trim, empty, length 8/9, alphanumeric, canonical uppercase, backend ASCII mismatch fixture.
- Login: invalid credentials, inactive account, activation required, returning user.
- Activation: success, duplicate nickname, already activated, expired session.
- Session: restore before expiry, clear after expiry, logout, centralized auth error transition.
- API envelope: nested data success, flat success, invalid JSON, empty response, backend error.
- Widget tests for loading/error/input/action states and tab shell navigation.

### Acceptance criteria

- Fresh install shows ORA Login, not Flutter counter/demo UI.
- Valid returning user enters the shell with nickname/division intact.
- First-time user must create a valid nickname before entering the shell.
- Expired session returns to Login consistently from the root controller.
- Logout clears the local session and returns to Login.
- ORA font, palette, crest/wordmark, card hierarchy, and five-tab layout match the Android identity.
- Android debug build succeeds; iOS host remains buildable and has no Android-only import in Dart domain/application code.
- No feature package beyond the approved foundation/auth need is added.

### Sprint review artifact

- Login -> Activation -> shell demonstration using test backend/fixture and live backend when credentials are available.
- Contract matrix showing exact parity for login/activation/error codes.

## Sprint 2 - Read-Side Feature Parity and Local Activity Foundation

### Goal

Deliver the non-tracking ORA experience using live API contracts: Home, user stats, Quest progress/claims, Guild, leaderboard, Profile, Settings, and a local final-activity/history foundation ready for Sprint 3.

### In scope

#### API repositories and controllers

- User stats repository/controller.
- Quest master/progress/claim repository/controller.
- Guild summary and Guild directory repository/controller.
- Leaderboard repository/controller for both scopes and all three metrics.
- Feature-specific normalized failures while preserving current user-facing messages.
- Contract fixtures for all 13 actions, including flat/nested success shapes.

#### Screens and state

- Home: branding, welcome, Adventurer Card, XP/level, latest local adventure placeholder/data, manual-sync entry state.
- Quest: refresh-on-entry, master fallback, progress, all current visual states, claim button, Guild reward block, stats refresh after claim.
- Guild: summary, active members, Guild directory, current-guild highlight, loading/error/empty states.
- Leaderboard: GLOBAL/GUILD, XP/distance/runs, current user rank, `NO_GUILD`, retry.
- Profile: account status, remote totals, XP/level, local Adventure Log, per-activity sync state.
- Settings: account, run/data safety copy, about, back, logout.

#### Storage foundation

- Define storage interfaces and schema version strategy.
- Implement `FinalActivity` equivalent to current `ActivityEntity` with owner isolation and stable statuses.
- Implement owner-scoped latest/list/aggregate queries.
- Add migration fixture representing Android `ora.db` version 1 fields, even if direct cross-app database import is not required.
- Do not yet implement active RunSession/LocationPoint/RunEvent behavior; only reserve/version the storage architecture if necessary.

### Explicitly out of scope

- Real GPS stream, permissions, foreground/background service.
- Run state machine and finalization from actual tracking.
- Durable retry execution and backend activity upload.
- Route viewer.
- Nickname rename.

### Tests

- User stats parsing, default stats, owner mismatch protection.
- XP/level display and current `totalXp / nextLevelXp` visual progress behavior.
- Quest fallback and all Quest state/claim rules from Android tests.
- Guild unassigned/inactive/legacy metadata states and active-member filtering fixtures.
- Leaderboard metric/scope forwarding, tie order, top-50/current rank, empty/no-guild states.
- Owner isolation, latest order, aggregates, primary-key duplicate, PENDING/SYNCED display.
- Widget tests for all loading/error/empty states and compact layouts at supported text scales.

### Acceptance criteria

- Logged-in user can navigate every non-Run screen with no demo placeholders.
- Live or fixture data renders the same fields and status semantics as Android.
- Quest claim is concurrency-guarded and refreshes user stats on success.
- Guild leaderboard does not displace the member and Guild directory views.
- Profile history never shows another NIK's local activities.
- Settings logout uses the Sprint 1 centralized session flow.
- App operates in a controlled offline/read-error state without crashing.
- Android and iOS builds remain valid; no GPS/native implementation has leaked into feature controllers.

### Sprint review artifact

- End-to-end non-tracking walkthrough plus a contract-fixture report for all API actions.

## Sprint 3 - Offline Tracking Engine, Native Adapters, and Recovery

### Goal

Build the complete offline-first Tracking Engine and native Android/iOS location adapters. A run must start, acquire GPS, track, pause/resume, survive UI backgrounding, persist continuously, recover after interruption, and finalize locally without any network dependency.

### In scope

#### Pure Dart domain

- `RawLocationSample`, accepted/rejected point, quality class, rejection reason.
- Versioned `TrackingPolicy` with safe defaults.
- Port current Android constants as a named parity profile.
- Coordinate, freshness, order, accuracy, duplicate, displacement, speed/jump, gap, pause-boundary gates.
- Quality bands and small confirmation/continuity window required by blueprint.
- Geodesic/haversine distance engine validated against Android/reference fixtures.
- Active/elapsed time and pace engine; current backend duration remains active time.
- Explicit state machine: IDLE, START_REQUESTED, ACQUIRING_GPS, RUNNING, PAUSED, REACQUIRING, FINALIZING, FINISHED, RECOVERABLE_SESSION.

#### Persistence and recovery

- Implement RunSession, LocationPoint, RunEvent, and the local side of SyncQueue.
- Transactionally persist point decision and critical session counters.
- Incremental accumulated distance plus final reconciliation from accepted points.
- Idempotent finalization that yields one immutable FinalActivity.
- Startup recovery detector and UI choices: Resume, End & Save, confirmed Discard.
- Long-gap recovery uses re-acquisition/new anchor.
- Explicit handling for finish before usable distance/duration; preserve data and apply an approved state, not silent deletion.

#### Native bridge

- Versioned MethodChannel/EventChannel contract: start, pause, resume, stop, getStatus, location stream, error stream.
- Normalize `permissionDenied`, `providerDisabled`, `serviceStartFailed`, `accuracyUnavailable`, `interrupted`, `unknown`.
- Android adapter using official location APIs/approved Fused provider and foreground location service.
- Android ongoing notification and pause/resume/finish actions mapped safely to persisted state.
- iOS Core Location adapter, background location capability, desiredAccuracy/distanceFilter policy, and stop on END.
- Contextual permission flows; do not request all permissions on first launch.

#### Run UI

- IDLE/acquiring/running/paused/reacquiring/finalizing/finished/recovery states.
- Large distance, active duration, pace, GPS quality, background state.
- Start, pause, resume, finish, done, and recovery actions.
- UI update throttling may differ from sample frequency without changing engine data.

### Explicitly out of scope

- Backend upload/retry execution.
- Route viewer rendering.
- Map/basemap/map matching.
- Auto-pause, elevation correction, live sharing, AI/ML classification.
- Field-tuned production threshold changes beyond safe defaults; tuning belongs to Sprint 4 evidence.

### Tests

- Port all Android `RunLocationEngineTest` and `RunPaceTest` cases.
- Add poor/weak/good quality band and confirmation-window cases.
- Future/stale/zero/negative/out-of-order timestamp cases.
- Spike candidate confirmed/rejected, stationary jitter, long gap, GPS reacquisition.
- Pause -> movement -> resume creates zero pause distance and a new anchor.
- Valid path expected distance, corner preservation, final reconciliation.
- Persistence transaction failure/restart and last-accepted-anchor restore.
- Finalization called twice creates one FinalActivity.
- Recovery Resume/End/Discard and owner/session isolation.
- Native contract serialization/error normalization tests.
- Android/iOS physical device smoke tests: foreground, lock screen, background, provider off, permission denial, process interruption.

### Acceptance criteria

- A run can complete entirely offline and remains visible locally.
- No raw/rejected point directly adds distance.
- Pause movement never contributes distance; resume always reacquires and creates a new anchor.
- Active time excludes pause; elapsed time is separately available.
- Killing/restarting the app after persisted progress offers a safe recovery flow and does not lose or duplicate the activity.
- END stops platform location activity promptly and finalizes locally before any network attempt.
- Android foreground notification accurately reflects state.
- iPhone lock-screen/background run continues within iOS capability rules; force-quit limitation is documented.
- Tracking Engine tests run without Flutter widgets or platform SDK objects.

### Sprint review artifact

- Offline run and recovery demonstration on one representative Android device and one iPhone, plus deterministic GPS fixture report.

## Sprint 4 - Sync, Route Viewer, Integration, and Cross-Platform QA

### Goal

Complete production parity around finalized activities: durable retry-safe sync, backend compatibility, Adventure Log integration, pure Flutter route viewing, field calibration, and release hardening across Android and iOS.

### In scope

#### Durable sync

- Versioned sync payload mapper preserving current fields.
- Stable activity/session id reused across all retries.
- Durable SyncQueue state, retryCount, lastAttemptAt, next-attempt/backoff policy, server ACK/status.
- SAVED and DUPLICATE both become SYNCED only after ACK is persisted.
- Startup, post-finalization, manual, and network-restored triggers with single-flight/mutex behavior.
- Pending status remains visible; finalized activity never disappears due to failed sync.
- Centralized handling for SESSION_EXPIRED/UNAUTHORIZED.
- Backward-compatible backend decision for Android/iOS `Source` and optional payload version. This is the only planned backend-contract change and requires explicit approval before implementation.

#### Route viewer

- Store/read accepted points for a finalized activity according to retention policy.
- Pure Flutter `CustomPainter`: fitted line, padding, aspect ratio, start marker, finish marker, pixel/RPG frame.
- Display-only point simplification for very long routes; original accepted points remain unchanged.
- No basemap, map tiles, map matching, pace coloring, or provider SDK.
- Viewer never calculates final distance.

#### Integration

- Home latest adventure refresh after local finalization and after sync.
- Profile Adventure Log shows local final result immediately and accurate pending/synced state.
- Successful sync refreshes user stats and Quest progress safely.
- Logout while a run is active follows an approved safe flow; it must not silently discard or reassign the run.
- Session/user ownership is enforced across run, history, queue, and recovery.

#### Field QA and calibration

- Controlled scenarios: open sky, known-distance loop/stadium, urban canyon, short tunnel/underpass, stationary 2-3 minutes, pause + 200-300 m movement, resume, poor GPS start, internet off, process restart, Android/iOS lock screen, low battery/power saver.
- Record accepted/rejected counts by reason, accuracy distribution, max gap, recovery count, policy version, raw-vs-accepted diagnostic distance in test mode, and battery delta.
- Change thresholds only in TrackingPolicy and add regression fixtures for every adjustment.
- Test multiple Android vendors and at least representative iPhone OS/device levels.

#### Release hardening

- Permission copy and store declarations.
- Data retention/privacy review for point diagnostics and tokens.
- Performance, memory, text scale, screen-reader, and battery review.
- Android signed build pipeline readiness; iOS signing/TestFlight readiness on Mac.
- Remove only cleanup candidates explicitly approved after parity review.

### Tests

- Sync SAVED/DUPLICATE/error/timeout/invalid response/session expiry.
- Queue survives restart; backoff and single-flight; no cross-owner upload.
- Server retry creates no duplicate row or XP.
- Route viewer consumes accepted points unchanged and does not affect distance.
- Route fitting for vertical/horizontal/single/duplicate-coordinate/large point sets.
- End-to-end offline finish -> pending -> reconnect -> synced -> stats/Quest refresh.
- Logout/relogin owner isolation and active-run guard.
- Cross-platform field matrix and battery measurements.

### Acceptance criteria

- Retry of the same finalized activity never creates duplicate backend activity or XP.
- Offline finish always yields a visible local activity and a durable pending queue item.
- Pending item becomes SYNCED only after a durable server acknowledgement.
- Pure Flutter route shape displays Start/Finish with no map dependency and cannot mutate tracking evidence.
- No catastrophic GPS spike appears in normal test scenarios.
- Pause boundary and recovery duplication tests pass 100%.
- Android and iOS demonstrate functionally equivalent start/pause/resume/end/offline/recovery behavior.
- Battery and performance are measured and accepted for the running use case.
- Release builds, permissions, privacy copy, and signing workflows are documented and validated.

### Sprint review artifact

- Complete Android/iOS ORA run walkthrough, field-test report, sync idempotency evidence, and release readiness checklist.

## 4. Dependency decision gates

Before adding any package, record:

1. Capability that cannot realistically be supplied by Flutter/Dart or the small native bridge.
2. Packages/native alternatives considered.
3. Binary size, maintenance, Android/iOS parity, license, and privacy impact.
4. Whether it affects Tracking Engine determinism or background lifecycle.
5. Approval and pinned version.

Likely decisions that need evidence, not assumptions:

- Local relational storage implementation.
- Secure session token storage.
- Whether Google Play services Fused Location remains the Android provider.

Explicitly disallowed in the initial plan:

- Google Maps, MapLibre, or another basemap provider.
- Riverpod, BLoC, GetX, or an external router without a proven need.
- A large Flutter location/background plugin used as a substitute for the blueprint's controlled native adapter.

## 5. Approval checkpoints

- **Before Sprint 1:** approve this analysis/plan and resolve only blocking scope questions.
- **Before Sprint 3 native work:** approve storage implementation and native bridge contract v1.
- **Before Sprint 4 backend work:** approve backward-compatible Source/payload-version behavior.
- **Before production:** approve TrackingPolicy values based on field evidence, not design-time guesses.

Until the first checkpoint is explicitly approved, implementation must not start.
