# ORA Android to Flutter Migration Analysis

Status: **analysis complete; implementation not started**  
Baseline date: 14 August 2026  
Android behavior reference: `D:\ORA-Development\ORA`  
Flutter architecture target: `ORA_Flutter_Master_Blueprint_v1.1_Detailed_Tracking.docx`  
Flutter target: `D:\ORA-Development\ora_flutter`

## 0. Executive summary

The Android application is a single-activity Jetpack Compose app backed by Google Apps Script/Google Sheets. It already implements login, first-time nickname activation, a five-tab application shell, home statistics, Quest progress and claims, Guild data, individual leaderboards, a local adventure log, manual/automatic activity sync, and an Android foreground GPS tracking service.

The Flutter target must preserve those behaviors while moving to a feature-first layered structure. The largest migration is not the Compose UI; it is the Tracking Engine. The current Android engine has useful and tested rules (monotonic timestamps, accuracy rejection, jitter deadband, plausible-speed rejection, pause/resume re-anchoring, and long-gap re-entry). However, it keeps its active run only in memory. It does not persist run sessions, GPS points, run events, or recovery state, and it has no iOS adapter. Blueprint v1.1 explicitly requires those capabilities.

Analysis scope:

- **113 Android/reference files inspected**: 109 files under `app`/`backend`, plus four root build/configuration files.
- The 109 application/backend files comprise 45 production Kotlin files, 13 Kotlin test files, one Apps Script backend, 47 files under `main/res`, one Android manifest, one app Gradle file, and one keep-rules file.
- **30 functional capability groups found**.
- **13 unique backend action contracts found** on one Apps Script deployment URL.
- **1 local SQLite table** found (`activities`), plus SharedPreferences session/profile keys.
- **8 backend Google Sheets schemas** found.
- No Android source file was modified.
- Flutter feature implementation remains untouched; only the requested documentation is added.

## 1. Source-of-truth rules used in this mapping

1. Existing Android business behavior is the parity reference unless a conflict is explicitly called out.
2. Blueprint v1.1 controls the new Flutter structure, tracking separation, offline persistence, native bridge, and Android/iOS parity.
3. A strange or dormant behavior is documented before any decision to remove or redesign it.
4. No database package, state-management package, map package, or location plugin is selected by this document.
5. Tracking and route viewing remain separate. The first route viewer is pure Flutter `CustomPainter` with no basemap.

## A. Current Android Architecture

### A.1 Runtime topology

```text
MainActivity (single Activity)
  -> ORATheme
  -> OraApp
       -> AuthViewModel / AuthRepository / LocalAuthStore
       -> authenticated five-tab Compose shell
            Home | Quest | Run | Guild | You
            -> feature ViewModels and repositories
            -> AppsScriptBackendApi
            -> OraDatabase / ActivityDao
       -> RunViewModel
            -> RunTrackingService (foreground service)
            -> RunSessionController singleton
            -> RunTracker (Fused Location Provider)
            -> RunLocationEngine
            -> ActivityRepository / ActivitySyncManager

AppsScriptBackendApi
  -> one Google Apps Script `/exec` URL
  -> `action`-based GET/POST dispatch
  -> Google Sheets master and transaction sheets
```

### A.2 Component inventory and responsibility

| Area | Android component | Current responsibility | Migration note |
|---|---|---|---|
| Entry | `MainActivity.kt` | Edge-to-edge window and Compose root | Replace with Flutter entry; keep only native bridge/bootstrap work in platform hosts. |
| App shell | `ui/OraApp.kt` | Auth-stage switch, five tabs, settings overlay, back-to-exit, shared ViewModels | Split app bootstrap, session gate, and navigation. Use Flutter `Navigator`/shell state. |
| Auth | `AuthViewModel`, `AuthRepository`, `LocalAuthStore` | Login, activation, restore/expiry, logout, dormant local rename | Move validation/domain rules out of widgets; isolate API and local credential/session storage. |
| Network | `backend/OraBackendApi.kt` | `HttpURLConnection`, JSON encoding/decoding, 15 s connect and 20 s read timeout | Implement a Dart API client with `dart:io` and `dart:convert`; keep action strings and payload names stable. |
| Feature data | Quest/Guild/Leaderboard/UserStats repositories and ViewModels | Remote reads, UI state, refresh, coarse user-facing errors | Use feature application controllers and infrastructure repositories. |
| Local data | `OraDatabase`, `ActivityDao`, `ActivityRepository` | Raw `SQLiteOpenHelper`, final-activity persistence, owner-scoped query streams | Preserve schema semantics, then extend storage to blueprint session/point/event/queue responsibilities. |
| Sync | `ActivitySyncManager`, `ActivityHistoryViewModel` | Sequential pending sync, duplicate ACK handling, manual/automatic refresh | Create an idempotent sync coordinator independent from tracking. |
| Tracking source | `RunTracker` | Google Play services Fused Location updates at high accuracy | Android-native location adapter behind a versioned platform-channel contract. |
| Tracking service | `RunTrackingService` | Foreground service, ongoing notification, pause/resume/finish actions, `START_STICKY` | Android-specific adapter/service; do not port lifecycle code into Dart UI. |
| Tracking logic | `RunLocationEngine`, `RunTrackingConfig` | Validation, jitter/speed/gap filtering, accepted distance | Port core rules into pure Dart domain code, then extend per blueprint without silently changing existing thresholds. |
| Run orchestration | `RunSessionController` | In-memory state, timer, location decisions, final save, auto-sync | Replace singleton coupling with `RunController` + coordinator + repositories + recovery service. |
| UI | Compose screens/components/theme | Pixel/RPG presentation, loading/error/empty states | Rebuild hierarchy as Flutter widgets; do not translate XML/Compose one-to-one. |
| Backend | `backend/Code.gs` | Auth/session, masters, activity ledger, XP/level, Quest, Guild, leaderboard | Contract remains unchanged during migration analysis. Compatibility changes require a separately approved backend plan. |

### A.3 Architecture characteristics

- UI is 100% Jetpack Compose; there are no Fragments.
- There is one Android `Activity` and one declared `Service`.
- There are no `Worker`, `BroadcastReceiver`, Room entity/DAO annotations, or WorkManager jobs.
- Local database access uses raw `SQLiteOpenHelper`, despite DAO-style interfaces.
- UI state uses Kotlin `StateFlow`/`SharedFlow`; repositories use coroutines and `Dispatchers.IO`.
- Run state is process-memory state in a global singleton. Only a finished activity is persisted.
- Backend errors are application-level JSON errors; the Apps Script handler does not set distinct HTTP error codes.
- The backend is data-driven through Config, Level, Quest, Participant, and optional Guild master sheets.

## B. Feature Inventory

No functional feature is marked `OBSOLETE` in this analysis. Dormant or unused code/assets are listed separately and must not be removed without approval.

| # | Capability found | Status | Evidence / preserved behavior |
|---:|---|---|---|
| 1 | NIK + four-digit PIN login | MUST MIGRATE | Client trims NIK; PIN must be exactly four numeric characters; backend checks participant and ACTIVE status. |
| 2 | First-login nickname activation | MUST MIGRATE | Required when backend nickname is blank; nickname is normalized to uppercase by Android before submit. |
| 3 | Session restore, expiry, and logout | MUST MIGRATE | 30-day backend session, local expiry check, local logout. No refresh or server revoke. |
| 4 | Local-only nickname rename path | CAN SIMPLIFY | Repository/ViewModel and tests exist, but no UI calls it and backend forbids post-activation changes. Treat as a conflict, not an active feature. |
| 5 | Authenticated five-tab shell | MUST MIGRATE | Home, Quest, centered/emphasized Run, Guild, You. |
| 6 | Double-back-to-exit behavior | ANDROID SPECIFIC | Two back presses within 2 seconds exit; settings consumes back first. iOS needs platform-appropriate navigation. |
| 7 | Home identity and last adventure | MUST MIGRATE | OTO branding, welcome, stats card, latest local activity. |
| 8 | User XP and level display | MUST MIGRATE | Backend totals/levels are authoritative; local activity totals are not used as backend XP. |
| 9 | XP progress bar | MUST MIGRATE | Current display uses `totalXp / nextLevelXp`, clamped 0..1; preserve until an approved rule changes it. |
| 10 | Active Quest master and progress | MUST MIGRATE | Authenticated progress endpoint with fallback to public Quest master on any failure. |
| 11 | Quest reward claim | MUST MIGRATE | Idempotent backend claim; guild reward intentionally blocked; successful claim refreshes stats. |
| 12 | Guild summary | MUST MIGRATE | Division-based membership with Guild_Master metadata fallback. |
| 13 | Guild active member list | MUST MIGRATE | Only ACTIVE participants appear; totals come from User_Stats. |
| 14 | Guild directory | MUST MIGRATE | Active master guilds plus legacy division buckets; current guild highlighted. |
| 15 | Global/Guild leaderboard | MUST MIGRATE | Scope GLOBAL/GUILD; metrics XP, distance, runs; up to 50 rows. |
| 16 | Profile and RPG statistics | MUST MIGRATE | Identity, guild, XP/level, backend totals, settings entry. |
| 17 | Settings/about/data-safety page | MUST MIGRATE | Read-only account/tracking/data/about information and logout. |
| 18 | Adventure log/history | MUST MIGRATE | Owner-scoped local activities, newest first, per-item sync state. |
| 19 | Local activity totals | MUST MIGRATE | Count, distance, and active duration queries; UI mainly uses backend totals. |
| 20 | Contextual location/notification permissions | ANDROID SPECIFIC | Fine location and Android 13+ notification permission are required before start. |
| 21 | High-accuracy GPS provider | ANDROID SPECIFIC | Fused provider, 1 s target/min interval, 2 m min displacement. |
| 22 | Foreground run service and notification actions | ANDROID SPECIFIC | Persistent notification with pause/resume/finish; service type `location`. |
| 23 | GPS quality filtering | MUST MIGRATE | Coordinate, freshness, order, accuracy, duplicate, jitter, speed, and gap checks. |
| 24 | Accepted-segment distance | MUST MIGRATE | Android `Location.distanceBetween`; only accepted segments accumulate. |
| 25 | Active duration and pace | MUST MIGRATE | Timer starts after first accepted baseline; pause time excluded; pace hidden below 20 m. |
| 26 | Manual pause/resume boundary | MUST MIGRATE | Tracker stops on pause; resume resets baseline; movement during pause is zero distance. |
| 27 | Finish, local save, and summary | MUST MIGRATE | Final summary saved locally before/independently of successful sync. |
| 28 | Automatic/manual pending activity sync | MUST MIGRATE | Startup retry, post-save auto-sync, and manual sync; failure remains pending. |
| 29 | Duplicate protection | MUST MIGRATE | Local primary key plus backend `(NIK, ActivityId)` idempotency; DUPLICATE is treated as synced. |
| 30 | Pixel/RPG visual system and assets | MUST MIGRATE | Press Start 2P, forest/gold palette, pixel badges, pixel illustrations, compact cards. |

### B.1 Proven dormant or unused items

- `AchievementSlot` has no production caller.
- `RunViewModel.pauseForBackground()` is a deliberate no-op and has no caller.
- `QuestRepository.fetchActiveQuests()` is test-covered but production uses `fetchQuestsWithProgress()`.
- `AuthViewModel.renameNickname()` has no UI caller.
- `email.png` and `notification.png` have no resource reference.
- Default purple/teal color resources are not used by the ORA Compose theme.
- The generated `ExampleUnitTest`/`ExampleInstrumentedTest` only test template behavior.

These are candidates for later cleanup, not migration-time deletion. `app.png` is used by the manifest even though it has no Kotlin reference; launcher foreground/background XML is referenced through mipmap XML.

## C. Screen Mapping

### C.1 Navigation map

| Android screen/state -> Flutter target | Entry action | State/data read | State/data written / next action |
|---|---|---|---|
| `LoginScreen` -> `features/auth/presentation/login_screen.dart` | App starts with no valid session | NIK/PIN input; auth error/loading | POST login; go to Activation or authenticated shell. |
| `ActivationScreen` -> `features/auth/presentation/nickname_activation_screen.dart` | Login returns `requiresNicknameActivation` | Division/Guild and pending session token/expiry | POST nickname; persist profile/session; enter shell. |
| `AuthenticatedOraApp` -> `app/app_shell.dart` | Valid restored/new session | Current user, selected tab, settings overlay | Changes selected tab; owns top-level feature controller lifetimes. |
| `HomeScreen` -> `features/home/presentation/home_screen.dart` | Home tab | Latest local activity, remote user stats, sync state | Manual sync; refresh Quest after sync callback. |
| `QuestScreen` -> `features/quest/presentation/quest_screen.dart` | Quest tab; auto-refresh on first composition | Quest list/progress/claim state | Refresh, claim reward, refresh user stats on success. |
| `RunScreen` IDLE/TRACKING/PAUSED -> `features/run/presentation/run_screen.dart` | Run tab and action buttons | Run state, GPS status, distance, active time, pace | Start permission flow; pause/resume/end via RunController. |
| Run `ResultSummary` -> `features/run/presentation/activity_summary_screen.dart` | END reaches FINISHED | Final local summary and save state | DONE clears presentation session; local activity remains. |
| `GuildScreen` MEMBERS -> `features/guild/presentation/guild_screen.dart` | Guild tab, default sub-tab | Guild summary and active members | Refresh only. |
| `GuildScreen` LEADERBOARD -> `features/leaderboard/presentation/leaderboard_panel.dart` | Guild sub-tab | Scope, metric, rows, current rank | Select GLOBAL/GUILD and XP/DISTANCE/RUNS; fetch board. |
| `GuildScreen` GUILDS -> `features/guild/presentation/guild_directory_panel.dart` | Guild sub-tab | Guild directory and current guild | Read-only current behavior. |
| `ProfileScreen` -> `features/profile/presentation/profile_screen.dart` | You tab | Remote stats, local activity list/totals, sync state | Manual sync; open settings. |
| Profile Adventure Log -> `features/activity_history/presentation/activity_history_section.dart` | Embedded in Profile | Owner-scoped local activities | Read-only; sync state shown per item. |
| `SettingsScreen` -> `features/settings/presentation/settings_screen.dart` | Gear icon from Profile | Current session/account metadata | Back; logout clears run summary/user and local auth session. |

### C.2 Navigation behaviors to preserve

- Auth stage is the root gate; feature screens must not render without a valid `UserSession`.
- Switching tabs does not create separate deep routes in Android; Flutter may preserve each tab state using an indexed shell.
- Settings hides the bottom navigation and returns to the previously selected tab.
- Leaderboard remains a Guild sub-view in current UX, not a top-level tab.
- Activity summary and Adventure Log are embedded views today. They may become named Flutter routes only if behavior stays equivalent.
- Do not carry Android's exit-on-back behavior to iOS. On Android it can be reproduced at the app shell.

## D. Business Logic Mapping

| Android component -> responsibility -> Flutter target layer | Rules that must be preserved |
|---|---|
| `AuthValidation.kt` -> credential/nickname validation -> Auth domain | PIN empty/exactly 4/digits only; nickname trim, non-empty, max 8 client baseline, alphanumeric; canonical uppercase. |
| `AuthRepository` -> auth workflow -> Auth application/domain service | Login result branches to activation when nickname missing; expiry is client-now + server TTL; backend errors map to current user messages. |
| `LocalAuthStore` -> session/profile persistence -> Auth infrastructure | Expired sessions clear locally; nickname owner keys exist only for local rename behavior. |
| `UserStatsRepository` -> authoritative XP/level totals -> Stats infrastructure | Do not calculate account level from local unsynced history. Backend response is authoritative. |
| `QuestRepository` -> master/progress/claim -> Quest infrastructure | Progress failure falls back to master list; claim does not run concurrently; successful claim updates the one Quest and refreshes stats. |
| `QuestScreen` helpers -> Quest presentation state -> Quest presentation/application | Claimed wins visual priority; completed is claimable unless blocked; unknown/no-guild/unsupported are non-claimable. |
| Backend `calculateQuestProgress_` -> Quest calculation -> remains backend contract | DISTANCE=sum km; RUN_COUNT=count; RUN_DAYS=unique local dates; SINGLE_RUN=max km; DURATION=sum seconds; XP=total or period activity XP; STREAK=longest consecutive date sequence; GUILD_DISTANCE=sum active guild member activities. |
| Backend `calculateActivityXp_` -> XP calculation -> backend authority | COMPLETED only; `round(distanceKm * XP_PER_KM)`; fallback XP_PER_KM=10. |
| Backend `getLevelByXp_` -> level selection -> backend authority | Highest active level whose required XP <= total; next threshold is first greater value. |
| Guild backend functions -> membership and aggregation -> backend authority | Division comparison is trimmed/case-insensitive; active participants contribute; legacy division fallback remains valid. |
| `LeaderboardRepository` + backend sort -> ranking -> backend authority | Descending selected metric; tie-break nickname then NIK; ranks before top-50 slice; current user rank may exist outside returned top 50. |
| `FinishedRunActivity.toEntity` -> final activity normalization -> Activity domain/infrastructure | Invalid/negative distance becomes 0; negative active duration becomes 0; non-positive pace becomes null; initial status PENDING. |
| `ActivityRepository` -> final save -> Activity application | UUID activity ID; primary-key conflict is duplicate; activity ownership snapshot captured at finish. |
| `ActivitySyncManager` -> retry/idempotency -> Sync application | Owner isolation; only positive duration and positive finite distance upload; SAVED and DUPLICATE both mark SYNCED; individual failures do not abort the loop. |
| `RunTrackingConfig` -> tracking thresholds -> Run domain `TrackingPolicy` | Preserve current values as a named Android-parity policy/fixture before field tuning. |
| `RunLocationEngine` -> point decision/distance -> Run domain | Only accepted points add distance; rejected point does not replace anchor except exact-coordinate timestamp refresh; gap >10 s re-anchors; pause/resume resets anchor. |
| `RunSessionController` -> run state/timer/finalization -> Run application | Active timer starts at first valid baseline; pause time excluded; finish allowed from tracking or paused; tracker stops before final save. |
| `RunViewModel` pace functions -> metric formatting/calculation -> Run domain/presentation | Pace = active seconds / km, rounded to nearest second; unavailable for distance <20 m or invalid duration/distance. |

### D.1 Important exact constants in the current tracking policy

| Parameter | Current Android value | Blueprint mapping |
|---|---:|---|
| Target update interval | 1,000 ms | `sampleIntervalTarget` safe default/Android adapter config. |
| Minimum update interval | 1,000 ms | Adapter-specific request constraint. |
| Provider minimum displacement | 2 m | Adapter request filter, not the only domain movement filter. |
| Maximum accepted accuracy | 30 m | Current hard cutoff; blueprint adds quality bands around it. |
| Minimum segment | 2 m | `minDisplacementForDistance`. |
| Maximum jitter threshold | 5 m | Dynamic deadband ceiling. |
| Accuracy jitter factor | 0.25 x sum of adjacent accuracies | Preserve in parity fixture before changing. |
| Maximum plausible speed | 12 m/s | `maxPlausibleRunningSpeed`. |
| Maximum point age | 15 s | `stalePointMaxAge`. |
| Re-entry gap | >10 s | `gapReanchorThreshold`. |
| Minimum pace distance | 20 m | Presentation/domain pace availability rule. |

### D.2 Behavioral conflicts requiring a decision, not an implicit refactor

1. **Nickname rename:** Android has a local rename method, but no UI invokes it and the backend rejects a different nickname after activation. Flutter should implement activation only until a backend-supported rename decision exists.
2. **Nickname character rule:** Android `Char.isLetterOrDigit` accepts broader Unicode; backend accepts ASCII `[A-Za-z0-9]`. Backend is the effective contract. Keep the UI message and align validation only through an approved parity change.
3. **Nickname max length:** Android hardcodes 8; backend can read `NICKNAME_MAX_LENGTH`, fallback 8. Until config is fetched for auth, 8 is the safe parity value.
4. **Quest fallback:** any authenticated progress failure falls back to public master data. This can make an expired session look like zero Quest progress. Preserve behavior initially but expose the risk in centralized error handling.
5. **Elapsed versus active time:** current UI/payload stores active duration only; blueprint defines both elapsed wall time and active time. Flutter must add elapsed time without changing current pace and backend `durationSec` semantics unless approved.
6. **Activity source:** backend writes `Source='ANDROID'` regardless of payload. This is incompatible with truthful iOS provenance and needs a backward-compatible backend versioning decision.
7. **Finish with invalid metrics:** UI can finish while acquiring GPS. Local save can create a zero-distance/zero-duration PENDING row that sync will always skip. Do not silently delete it; define a product rule in Sprint 3/4.

## E. Backend/API Mapping

### E.1 Transport contract

- Deployment URL: the constant `ORA_BACKEND_URL` in Android points to one Google Apps Script `/exec` endpoint.
- Content type: `application/json; charset=utf-8`; response accept: JSON.
- Android timeouts: 15,000 ms connect, 20,000 ms read.
- GET uses query `action`; POST uses a JSON body containing `action`.
- Standard success envelope: `{ok:true, apiVersion:"1.0", timestamp, data:{...}}`.
- Several read endpoints deliberately return fields at the root instead of under `data` (stats, Guild, directory, leaderboard, Quest progress). Android handles both by returning `data` when present, otherwise the root object.
- Error envelope: `{ok:false, apiVersion, timestamp, error:{code,message}}`.
- Handlers do not assign distinct HTTP error status codes. The mobile client must evaluate `ok` and `error.code`, not rely only on HTTP status.
- There is no generic API retry. Activity sync is the only retryable workflow; other features expose manual refresh or a coarse error.

### E.2 Action inventory (13 unique contracts)

| Action | Method/auth | Request | Success data/fields | Important errors/status |
|---|---|---|---|---|
| `health` | GET, public | `?action=health` | `data.service`, `data.status=UP`, spreadsheet name | UNKNOWN_ACTION, backend initialization/schema errors. |
| `config` | GET or POST, public | action only | `data.config` key/value object; active rows only, typed TEXT/NUMBER/BOOLEAN | Schema errors. |
| `levels` | GET or POST, public | action only | `data.levels[]`: level, levelName, requiredTotalXp | Invalid rows filtered; empty list possible. |
| `quests` | GET or POST, public | action only | `data.quests[]`: questId/name/type/target/unit/reward/period/start/end | Only active and in-date rows. |
| `login` | POST, public | `nik`, `pin` | sessionToken, expiresInSeconds, participant, requiresNicknameActivation | MISSING_CREDENTIALS, INVALID_CREDENTIALS, ACCOUNT_INACTIVE. |
| `activateNickname` | POST, session | sessionToken, nickname | participant, nicknameSaved, alreadyActivated | UNAUTHORIZED, SESSION_EXPIRED, INVALID_NICKNAME, NICKNAME_TAKEN, NICKNAME_ALREADY_ACTIVATED, participant/account errors. |
| `submitActivity` | POST, session | sessionToken, `activity` object | status SAVED or DUPLICATE; activityId; message | Missing/invalid activity fields; session/account; stats/level/schema errors. |
| `getUserStats` | POST, session | sessionToken | root `stats` object | Session/account errors; default zero stats when no row. |
| `getGuildSummary` | POST, session | sessionToken | root status, guild nullable, members[] | `UNASSIGNED` is a success state; account/session errors. |
| `getGuildDirectory` | POST, session | sessionToken | root guilds[] | Account/session/schema errors. |
| `getLeaderboard` | POST, session | sessionToken, scope, metric | root scope, metric, status, leaderboard[], currentUserRank nullable | INVALID_LEADERBOARD_SCOPE/METRIC; `NO_GUILD` is a success state. |
| `getQuestProgress` | POST, session | sessionToken | root quests[] with progress/claim fields | Session/account/schema errors; per-Quest UNKNOWN_TYPE/NO_GUILD are data states. |
| `claimQuestReward` | POST, session | sessionToken, questId | status CLAIMED or ALREADY_CLAIMED; claim; CLAIMED also includes userStats | Missing/inactive/not-completed/unsupported Quest, pending claim, session/account errors. |

### E.3 Activity payload contract

```json
{
  "action": "submitActivity",
  "sessionToken": "...",
  "activity": {
    "activityId": "stable UUID",
    "startTime": "ISO_OFFSET_DATE_TIME",
    "endTime": "ISO_OFFSET_DATE_TIME",
    "durationSec": 360.0,
    "distanceKm": 1.0,
    "avgPace": "06:00",
    "deviceTime": "ISO_OFFSET_DATE_TIME"
  }
}
```

Rules:

- `activityId`, start, end, positive duration, and positive distance are mandatory.
- Server identity comes only from the session; client nickname/division snapshots are not trusted for the row.
- Duplicate detection is `(NIK, ActivityId)`.
- A successful insert creates a COMPLETED Activities row and updates User_Stats under one script lock.
- If stats aggregation fails, the newly appended activity row is deleted so a retry remains valid.
- Server XP is recomputed from distance and config; the mobile client does not submit XP.
- Current server source is hardcoded to `ANDROID`.

### E.4 Session behavior

- TTL is 2,592,000 seconds (30 days).
- Token is two concatenated UUIDs.
- Backend stores a SHA-256-derived property/cache key, with persistent Script Properties and up to 6-hour cache copies.
- Expired/malformed sessions are deleted on access; expired-property cleanup runs when saving a new session.
- Android stores the raw token and expiry in private SharedPreferences.
- Logout only clears local storage; no backend revoke endpoint exists.

### E.5 Retry and error mapping

- Activity sync reads owner-scoped PENDING/LOCAL_ONLY rows, uploads sequentially, catches each failure, and continues.
- No retry count, next-attempt timestamp, exponential backoff, connectivity observer, or background worker exists.
- Retry triggers are: authenticated startup, successful finish/save, Home manual sync, and Profile manual sync.
- SAVED and DUPLICATE are both terminal acknowledgements locally.
- Auth maps selected backend errors to user-friendly text; other features usually collapse all exceptions to one feature-specific message.
- Session expiry is not centrally propagated to logout from Quest/Guild/Leaderboard/Stats/Sync.

## F. Database Mapping

### F.1 Current local SQLite schema

Database: `ora.db`, version 1. There is no upgrade implementation beyond a no-op.

| `activities` column | Constraint/meaning | Flutter responsibility |
|---|---|---|
| `activityId` | TEXT primary key | Stable final activity/sync id. |
| `ownerNik` | TEXT NOT NULL; indexed with start/created time | Mandatory owner isolation. |
| `nicknameSnapshot` | nullable TEXT | Display/audit snapshot only. |
| `divisionGuildSnapshot` | nullable TEXT | Display/audit snapshot only. |
| `startDateTimeMillis` | INTEGER NOT NULL | Wall-clock run start request time. |
| `endDateTimeMillis` | INTEGER NOT NULL | Wall-clock finish time. |
| `distanceMeters` | REAL NOT NULL | Accepted accumulated distance. |
| `activeDurationMillis` | INTEGER NOT NULL | Excludes pause and GPS acquisition before first baseline. |
| `averagePaceSecondsPerKm` | nullable INTEGER | Final active pace; null when unavailable. |
| `createdAtMillis` | INTEGER NOT NULL | Local row creation time. |
| `syncStatus` | TEXT NOT NULL | LOCAL_ONLY, PENDING, or SYNCED. |

Indexes:

- `(ownerNik, startDateTimeMillis)`
- `(ownerNik, createdAtMillis)`

There are no foreign keys and no persisted GPS points or active sessions.

### F.2 Key-value auth storage

Private SharedPreferences file `ora_auth` stores logged-in flag, NIK, nickname, division, raw session token, and expiry. It also stores per-NIK profile nickname/division plus nickname-owner keys used only by local rename logic. Android disables application backup (`allowBackup=false`), which reduces accidental token/database cloud backup.

### F.3 Android -> Flutter storage mapping

| Android table/model -> Flutter model/storage responsibility | Mapping |
|---|---|
| `ActivityEntity` -> `FinalActivity` | Preserve all existing fields and statuses; add payload version/server ACK metadata without changing current API payload by default. |
| `activities.syncStatus` -> `SyncQueue` + final activity status | Normalize queue mechanics separately while keeping PENDING/SYNCED visible to UI. Migration may initially derive queue state from the activity for compatibility. |
| In-memory `RunSessionController` fields -> `RunSession` | Persist sessionId, userId, lifecycle status, start/end, active and elapsed durations, accumulated distance, last accepted sequence, policy version, app version, sync status. |
| In-memory `GpsPoint`/decisions -> `LocationPoint` | Persist normalized raw sample, accepted flag, rejection reason, segment distance, quality class, provider metadata. |
| Start/pause/resume/end actions -> `RunEvent` | Persist ordered lifecycle events for deterministic recovery and pause boundaries. |
| No current equivalent -> `SyncQueue` | Payload version, retry count, last attempt, state, server ACK ID. |
| `LocalAuthStore` -> `SessionStore`/`ProfileCache` | Keep session storage behind an interface; decide secure native storage implementation during Sprint 1, not in this analysis. |

### F.4 Backend sheet schemas (8)

1. `Participants`: NIK, PIN, Nickname, Division_Guild, Status, Created_At, Updated_At.
2. `Config`: key, value, data type, description, active.
3. `Level_Master`: level, name, required total XP, active.
4. `Quest_Master`: identity, type, target/unit/reward, period/date range, active.
5. `Activities`: activity ledger and source/sync timestamps.
6. `User_Stats`: aggregate activities/distance/duration/XP/level and last activity.
7. `Quest_Claims`: idempotent per-user claim record and status.
8. `Guild_Master`: optional metadata/status/sort order; participant division remains membership source.

## G. Tracking Mapping

| Current Android behavior -> Flutter tracking blueprint target | Decision |
|---|---|
| Fused high-accuracy location request -> native `AndroidLocationAdapter` | ANDROID SPECIFIC. Keep behind `TrackingService` interface; provider choice must not leak to domain. |
| No iOS implementation -> `IOSLocationAdapter` using Core Location | New required adapter with background location capability and lifecycle tests. |
| `GpsPoint` with lat/lng/accuracy/elapsed nanos -> `RawLocationSample` | Add provider timestamp, receivedAt, optional speed/course/altitude, and safe provider metadata. |
| Coordinate range/finite check -> coordinate sanity gate | Preserve exactly. |
| Monotonic age check using elapsed realtime -> freshness/timestamp gate | Preserve monotonic logic on Android; normalize equivalent iOS timestamps. |
| Hard accuracy cutoff at 30 m -> quality bands + policy | Preserve cutoff as parity baseline; add EXCELLENT/GOOD/WEAK/POOR/INVALID classification. |
| Duplicate/out-of-order rejection -> duplicate/time-delta gate | Preserve; distinguish diagnostic zero-distance duplicate from invalid order. |
| Dynamic 2-5 m jitter deadband -> displacement gate | Preserve fixture; tune only through centralized TrackingPolicy and field evidence. |
| 12 m/s rejection -> implied-speed/jump gate | Preserve hard safety rule; blueprint adds candidate/confirmation window instead of treating every jump independently. |
| >10 s gap becomes new baseline -> gap re-anchor | Preserve. Persist event/reason for recovery diagnostics. |
| Pause stops updates and clears baseline -> PAUSED + resume re-acquisition/new anchor | Preserve as locked business behavior. |
| First valid point immediately becomes baseline -> ACQUIRING_GPS warm-up | Current version uses one acceptable point; blueprint requires multiple-signal quality/continuity warm-up. Treat as an explicit enhancement with regression tests. |
| Accepted segments use Android `Location.distanceBetween` -> pure Dart geodesic distance engine | Verify parity against fixtures; native provider must not calculate business distance. |
| Distance stored only in memory during run -> incremental transactional persistence | Required change; write point + critical session counters consistently. |
| Active timer starts at baseline -> active-time engine | Preserve active time; add elapsed wall time separately. |
| Foreground service + notification -> Android native service adapter | Keep active only during run. Dart UI sends commands through MethodChannel; location/error state through EventChannel. |
| `START_STICKY` with no persisted restore -> recoverable session workflow | Critical gap. Startup must locate RUNNING/PAUSED/FINALIZING records and offer Resume, End & Save, or confirmed Discard. |
| Finish stops tracker then writes final activity -> idempotent FINALIZING | Preserve ordering; finalization must be idempotent and transactionally produce one final activity/PENDING_SYNC. |
| Post-save immediate sync -> separate SyncController | Preserve trigger, but network must remain outside the tracking critical path. |
| No route point list/viewer -> accepted point repository + `OraRoutePainter` | New viewer reads accepted points only; it never calculates or mutates distance. |
| Diagnostics disabled in production -> structured debug/test diagnostics | Keep production lightweight; collect accepted/rejected counts, reasons, gap, accuracy, recovery count, policy version. |

### G.1 What is already good and should be retained

- Monotonic timestamp validation instead of UI receive time.
- Finite/range coordinate checks.
- Accuracy rejection, stale-point rejection, and out-of-order rejection.
- Accuracy-aware jitter deadband.
- Plausible-speed spike rejection.
- Conservative long-gap re-anchor.
- Pause/resume baseline isolation.
- Active-time pace and minimum-distance guard.
- Generation-based callback isolation so stopped tracker callbacks are ignored.
- Location updates stop on pause/finish; foreground notification is user-visible.

### G.2 What must change to meet blueprint v1.1

- Persist active session, points, events, counters, and recovery state.
- Expand the state machine beyond IDLE/TRACKING/PAUSED/FINISHED to include requested/acquiring/reacquiring/finalizing/recoverable/sync states.
- Introduce quality classes and a small confirmation/continuity window for weak/jump candidates.
- Version TrackingPolicy and bridge contracts.
- Normalize platform error codes.
- Add iOS Core Location adapter and cross-platform acceptance tests.
- Reconcile final distance from accepted points once at idempotent finalization.
- Keep route rendering fully outside the engine.

### G.3 Current failure/recovery behavior

- Permission denial/approximate location/notification denial prevents start and shows a warning.
- Provider unavailable keeps the run state and warns while waiting.
- Tracker request failure moves to IDLE, stops tracking, retains distance/duration only in memory, and resets start epoch.
- Process death loses `RunSessionController` and all active-run data. A restarted sticky service cannot reconstruct the run and stops itself if the singleton is IDLE.
- App UI backgrounding is intentionally not treated as pause; the foreground service continues.
- No boot receiver, background worker, or crash recovery record exists.

## H. UI Migration Mapping

### H.1 Visual identity to preserve

- Dark forest palette: deep forest backgrounds, forest/panel surfaces, cream text, gold primary, orange warnings, moss/teal/success accents.
- Press Start 2P display font at approximately 20/14/10 sp roles; default platform font for dense body values.
- Pixel/RPG identity through square-ish 3-8 dp radii, thin gold/brown borders, compact cards, badges, explicit iconography, and uppercase action copy.
- A large/emphasized Run destination in the five-item bottom navigation.
- OTO Runners community wordmark, adventure crest, character sprites, and stat icons.
- Lightweight screens: no tile map, no animated background, no large UI kit.

### H.2 Flutter widget translation

| Compose pattern | Flutter target |
|---|---|
| `MaterialTheme` dark scheme | `ThemeData`/`ColorScheme` in `app/theme`, with explicit ORA tokens. |
| `OraCard`, compact Guild/Quest cards | Shared `OraCard` plus feature-specific compact variants; avoid one over-configurable widget. |
| `OraScreenTitle` | Shared title widget with optional pixel asset/subtitle. |
| `PixelBadge` | Bordered `Container` + Press Start text; semantic label retained. |
| `StatLine`, `CompactStat`, `XpProgress` | Shared stats widgets; progress formula remains application-provided. |
| Compose `NavigationBar` | Flutter `NavigationBar` or custom lightweight shell preserving size/color hierarchy. |
| `Column.verticalScroll` | `ListView`/`CustomScrollView` as appropriate to avoid unbounded overflow. |
| `LazyColumn` activity log | `ListView.builder`/sliver list keyed by activityId. |
| Loading/error/empty cards | Reusable state panels with feature-specific retry callbacks. |
| Run metrics | Large stable numeric layout; throttle UI updates independently from GPS sampling if needed. |
| Future route | `CustomPaint` fitted to accepted points with padding/aspect ratio and Start/Finish markers. |

### H.3 Accessibility and usability requirements

- Keep icon semantic labels; never use pixel imagery as the only status signal.
- Ensure Press Start 2P is not used for long body text or tiny critical messages.
- Preserve large 60-64 dp primary run buttons and clear start/pause/resume/finish distinction.
- Respect safe areas, text scale, Android/iOS permission messaging, and screen-reader order.
- Do not copy the current 8 sp Guild/Quest text blindly; preserve density and identity while meeting readable text-scale tests.

## I. Dependency Inventory

### I.1 Current Android dependencies

| Dependency/group | Current function | Flutter replacement/need | Built-in/native bridge assessment |
|---|---|---|---|
| Android Gradle Plugin 9.3.1 / Kotlin 2.2.10 | Android build/Compose compiler | Flutter Android host build only | Generated Flutter platform toolchain. |
| Compose BOM 2026.02.01, Compose UI/graphics/tooling | Declarative UI | Flutter widgets/rendering | Flutter SDK built-in. |
| Material3 + extended Material icons | Components/navigation/icons | Flutter Material plus ORA PNG assets | Built-in; do not add UI kit. |
| Activity Compose 1.8.0 | Compose host | FlutterActivity | Generated host. |
| AndroidX Core KTX 1.10.1 | ContextCompat and Kotlin Android helpers | Native Android adapter only | Android platform dependency as needed. |
| Lifecycle runtime/ViewModel 2.6.1 | ViewModel scope and Compose state | ChangeNotifier/ValueNotifier/controllers | Flutter SDK baseline; no Riverpod/BLoC/GetX initially. |
| Kotlin coroutines/Flow (available through current graph) | Async work and UI streams | `Future`, `Stream`, ChangeNotifier/ValueNotifier | Dart built-in. Note current Gradle file has no explicit coroutine artifact. |
| Google Play services Location 21.3.0 | Fused location source | Native Android adapter | Keep only if explicitly chosen; no Flutter location plugin required by blueprint. |
| `HttpURLConnection` + `org.json` | HTTP and JSON | `dart:io` + `dart:convert` | Built-in. |
| Android `SQLiteOpenHelper` | Local final activity storage | Storage interface; implementation decision deferred | No package selected in analysis. Platform channel is possible but package choice should be evidence-based. |
| SharedPreferences | Session/profile key-value storage | SessionStore interface | Secure native bridge may be required for token protection. |
| Android Service/Notification APIs | Background run task | Android native service bridge | Native bridge required. |
| JUnit 4.13.2 | Unit tests | `flutter_test`/Dart test; native unit tests for adapters | Flutter SDK plus platform test frameworks. |
| AndroidX JUnit/Espresso/Compose UI test | Instrumented/UI test dependencies | Flutter integration/widget tests later | Current repo only has generated instrumented example. |

### I.2 Current Flutter scaffold dependencies

- `flutter` SDK.
- `cupertino_icons 1.0.8` (not required by the ORA design unless an iOS-standard icon is intentionally used).
- `flutter_test` SDK and `flutter_lints 6.0.0`.
- No package addition is approved by this analysis.

### I.3 Native bridge requirements

Native bridge is justified for:

- Android foreground location service and notification actions.
- Android location provider callbacks and service state.
- iOS Core Location/background lifecycle.
- Potential secure token storage if a standard-library-only solution is not adequate.

It is not justified for Quest/Guild/leaderboard/business rules, HTTP JSON, theme/widgets, distance math, point validation, or route rendering.

## J. Risk Register

| Severity | Risk | Evidence/impact | Mitigation / acceptance gate |
|---|---|---|---|
| CRITICAL | Active run is not persisted | Process kill loses timer, distance, points, owner, and finalization state. | Implement transactional RunSession/LocationPoint/RunEvent persistence and recovery before field release. |
| CRITICAL | iOS background tracking is absent | Entire native adapter/lifecycle/permission path is new. | Build iOS adapter behind same contract; physical iPhone lock/background/force-quit matrix. |
| CRITICAL | Duration is reported frozen on newer phones | Current active timer starts only after the first accepted GPS baseline; newer-device permission, acquisition, service, provider, battery, lifecycle, or UI-clock behavior may prevent/obscure that transition. | Sprint 3 must reproduce with event timelines, fix the identified layer, and pass old/new device regression. Sprint 4 revalidates before release. |
| HIGH | Tracking policy gap versus blueprint | One-point warm-up, no quality bands, no confirmation window, no point ledger. | Port current policy as regression baseline, then extend through versioned TrackingPolicy with fixtures. |
| HIGH | Current sticky service gives a false sense of recovery | Service restart cannot restore singleton state. | Recovery must be storage-driven; do not treat `START_STICKY` as persistence. |
| HIGH | Zero/invalid finished activity can remain pending forever | Finish can occur before GPS baseline; sync skips non-positive metrics. | Define explicit save/discard/invalid-local rule and test it; never silently delete user data. |
| HIGH | Session token stored as plain private preferences | Device compromise/backup configuration changes could expose token. | SessionStore abstraction and approved secure native storage; keep backup exclusion. |
| HIGH | Session expiry is not centralized | Feature calls may show generic offline errors without returning to login. | Normalize API errors and route UNAUTHORIZED/SESSION_EXPIRED through SessionController. |
| HIGH | Backend provenance is hardcoded ANDROID | iOS activities would be mislabeled. | Plan backward-compatible payload/source version with backend approval before iOS production sync. |
| HIGH | Local database has no migration strategy | DB version 1 upgrade is no-op; new run tables are substantial. | Versioned schema/migration tests and upgrade-from-current fixture. |
| HIGH | API success envelopes are inconsistent | Some data nested, some root; careless Dart parsing can break features. | Contract fixtures for all 13 actions and a tolerant, explicit response decoder. |
| HIGH | Retry queue lacks backoff and durable attempt metadata | Repeated manual/startup retries can hammer backend; no scheduling visibility. | Durable SyncQueue, bounded backoff, retryCount/lastAttempt, network-aware trigger. |
| HIGH | Nickname behavior conflicts | Local rename path diverges from immutable backend activation. | Do not expose rename in Flutter until product/backend contract is approved. |
| MEDIUM | Quest fallback masks auth/network errors | Master data may appear with zero progress. | Preserve initially; show stale/fallback state and let centralized session errors win. |
| MEDIUM | Android notification permission is a start prerequisite | Behavior is stricter than some OS requirements and differs on iOS. | Treat as existing Android rule; confirm product intent during native acceptance review. |
| MEDIUM | UI uses very small pixel font in dense Guild/Quest views | Readability/accessibility and text scaling risk. | Preserve character while introducing minimum readable sizes and scale/overflow tests. |
| MEDIUM | 25 PNG drawables are mostly 512x512 | Memory/bundle overhead if decoded at full resolution. | Reuse assets first; size/codec audit and lossless optimization without redrawing identity. |
| MEDIUM | No background worker for sync | Pending data waits for app/start/manual path. | Sprint 4 decision: app-lifecycle retry may be enough; add native scheduling only if required. |
| MEDIUM | Backend is Google Sheets under script locks | Latency/quota/concurrent writes can affect sync/claim. | Keep sequential idempotent writes, timeouts, clear pending UI, and load tests. |
| LOW | Dormant code/assets can confuse migration scope | Rename, AchievementSlot, unused icons/template tests. | Keep a quarantine list; remove only after parity acceptance. |

## K. Proposed Flutter Structure

```text
lib/
├─ main.dart
├─ app/
│  ├─ ora_app.dart
│  ├─ app_bootstrap.dart
│  ├─ app_shell.dart
│  ├─ navigation/
│  │  ├─ app_route.dart
│  │  └─ app_navigator.dart
│  └─ theme/
│     ├─ ora_colors.dart
│     ├─ ora_typography.dart
│     └─ ora_theme.dart
├─ core/
│  ├─ config/
│  │  ├─ app_config.dart
│  │  └─ build_info.dart
│  ├─ errors/
│  │  ├─ app_failure.dart
│  │  └─ backend_error.dart
│  ├─ network/
│  │  ├─ api_client.dart
│  │  ├─ api_envelope.dart
│  │  └─ api_contract_version.dart
│  ├─ persistence/
│  │  ├─ local_database.dart
│  │  ├─ transaction.dart
│  │  └─ schema_versions.dart
│  ├─ platform/
│  │  ├─ platform_capabilities.dart
│  │  └─ normalized_platform_error.dart
│  └─ diagnostics/
│     ├─ app_logger.dart
│     └─ diagnostic_policy.dart
├─ shared/
│  ├─ widgets/
│  │  ├─ ora_card.dart
│  │  ├─ ora_icon.dart
│  │  ├─ ora_screen_title.dart
│  │  ├─ pixel_badge.dart
│  │  └─ feature_state_panel.dart
│  └─ formatting/
│     ├─ duration_format.dart
│     └─ number_format.dart
├─ features/
│  ├─ auth/
│  │  ├─ domain/
│  │  ├─ application/
│  │  ├─ infrastructure/
│  │  └─ presentation/
│  ├─ home/...
│  ├─ user_stats/...
│  ├─ quest/...
│  ├─ guild/...
│  ├─ leaderboard/...
│  ├─ profile/...
│  ├─ settings/...
│  ├─ activity_history/
│  │  ├─ domain/
│  │  ├─ application/
│  │  ├─ infrastructure/
│  │  └─ presentation/
│  ├─ sync/
│  │  ├─ domain/
│  │  ├─ application/
│  │  └─ infrastructure/
│  └─ run/
│     ├─ domain/
│     │  ├─ run_session.dart
│     │  ├─ raw_location_sample.dart
│     │  ├─ accepted_point.dart
│     │  ├─ tracking_policy.dart
│     │  ├─ point_validator.dart
│     │  ├─ distance_engine.dart
│     │  ├─ pace_engine.dart
│     │  └─ run_state_machine.dart
│     ├─ application/
│     │  ├─ run_controller.dart
│     │  ├─ tracking_coordinator.dart
│     │  ├─ run_finalizer.dart
│     │  └─ run_recovery_service.dart
│     ├─ infrastructure/
│     │  ├─ location_bridge.dart
│     │  ├─ local_run_repository.dart
│     │  └─ run_sync_payload_mapper.dart
│     └─ presentation/
│        ├─ run_screen.dart
│        ├─ activity_summary_screen.dart
│        └─ ora_route_painter.dart
└─ models/  # only truly cross-feature immutable contracts; avoid dumping feature models here

assets/
├─ fonts/press_start_2p.ttf
├─ images/branding/
├─ images/navigation/
├─ images/stats/
└─ images/actions/

android/app/src/main/kotlin/.../tracking/
├─ AndroidLocationAdapter.kt
├─ OraRunForegroundService.kt
└─ LocationBridgeContract.kt

ios/Runner/Tracking/
├─ IOSLocationAdapter.swift
├─ OraLocationManager.swift
└─ LocationBridgeContract.swift

test/
├─ contract/
├─ fixtures/
└─ features/  # mirrors domain/application structure
```

Structure principles:

- Feature models live with their feature; only stable cross-feature contracts go in `lib/models`.
- Domain code has no Flutter widget, platform object, `MethodChannel`, SQLite, or HTTP dependency.
- Application controllers own use-case orchestration and expose immutable UI state.
- Infrastructure implements interfaces for API, local storage, and native bridge.
- Native adapters normalize samples/errors before Dart domain code sees them.
- Sync is a sibling subsystem, not a method inside the Tracking Engine.

## L. Migration Plan Summary

Detailed Sprint scope and acceptance criteria are in `docs/FLUTTER_4_SPRINT_PLAN.md`.

1. **Sprint 1 - Foundation, design system, and identity:** establish architecture, ORA theme/assets, API envelope, navigation/session gate, login/activation/session restore.
2. **Sprint 2 - Read-side feature parity:** Home, stats, Quest/claim, Guild, leaderboard, Profile/Settings, and local activity/history storage foundation using contract fixtures.
3. **Sprint 3 - Offline Tracking Engine and recovery:** pure Dart validation/state/distance/time, expanded local schema, Android/iOS bridge adapters, foreground/background lifecycle, pause/resume, finalization and crash recovery.
4. **Sprint 4 - Sync, route viewer, integration, and cross-platform QA:** versioned final payload, durable retry queue, `CustomPainter` route view, full Android/iOS field matrix, regression and release hardening.

Every Sprint must end with Android and iOS projects still buildable. No Sprint begins automatically from this analysis.

## Appendix 1. Asset Inventory

### Directly reusable in Flutter

- Font: `press_start_2p.ttf` (116,008 bytes).
- Branding: `app.png` (512x512 crest), `oto_runners.PNG` (709x236 wordmark).
- Main pixel illustrations: `run.png`, `adventure.png`, `you.png`, all 512x512 transparent PNG.
- Navigation: `home.png`, `quest.png`, `run.png`, `guild.png`, `you.png`.
- Stats/status/actions: `achievement`, `distance`, `duration`, `finish`, `level`, `location`, `lock`, `pace`, `pause`, `resume`, `settings`, `success`, `trophy`, `warning`, `xp`.

There are 25 PNG drawables, three drawable XML files, one font, and 12 mipmap launcher files. All PNG icons use 32-bit alpha. Most PNGs are 512x512; preserve originals first and optimize only after visual parity review.

### Android-only or requires conversion

- `ic_stat_ora_run.xml`: Android notification small icon; retain in Android native resources.
- Android adaptive launcher/background/foreground XML and density-specific WEBP launchers: platform host assets, not Flutter runtime assets.
- `email.png` and `notification.png`: currently unreferenced; keep quarantined until product confirms removal.

## Appendix 2. Existing automated behavior evidence

The inspected test suite covers:

- PIN and nickname limits.
- First-login activation, returning login, local rename token preservation.
- Activity field mapping, owner isolation, aggregates, order, and local duplicate ID.
- Sync SAVED/DUPLICATE/failure behavior.
- User stats, Quest, Guild, and leaderboard repository forwarding/empty states.
- GPS duplicate/invalid/poor/stale/out-of-order/jump/jitter/gap/pause/resume/valid accumulation.
- Pace calculations and minimum-distance behavior.
- Quest presentation states and blocked Guild rewards.

Missing automated coverage to add in Flutter includes active-session recovery, transactional point/session persistence, finalization idempotency, centralized session expiry, full API envelope fixtures, native bridge contract versions, iOS lifecycle, Android service restart, and route-viewer non-mutation.

## Appendix 3. Analysis stop condition

This document does not authorize Sprint 1. The next action must be an explicit approval or requested revision of this mapping and the four-Sprint plan.
