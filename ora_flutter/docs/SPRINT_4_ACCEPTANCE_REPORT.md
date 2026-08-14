# Sprint 4 Acceptance Report

Date: 2026-08-14  
Status: **implementation complete; release acceptance blocked by physical-device and iOS gates**

## Completed

- SQLite schema v4 durable sync queue with immutable versioned payload, retry count, attempt timestamps, exponential backoff, error code, and durable server ACK.
- `SAVED` and `DUPLICATE` are the only terminal acknowledgements; activity becomes `SYNCED` only in the same local transaction that persists the ACK.
- Owner NIK is checked at queue selection, claim, ACK, activity update, and route loading.
- Single-flight sync triggers run at startup, post-finalization, manual action, application resume, and restored backend-host reachability while the app is active.
- A successful upload refreshes local history, backend stats, and Quest progress.
- Pure Flutter `CustomPainter` route viewer uses only baseline/re-entry/accepted points. It does not recalculate distance or modify stored points.
- Active/recoverable tracking blocks immediate logout. The user may keep running or finish/save before logout; silent discard and ownership transfer are not allowed.
- Database migration, stable retry payload, `DUPLICATE` ACK, single-flight, route edge cases, and existing duration/recovery behavior are covered by automated tests.

## Verification evidence

- `flutter analyze`: PASS, no issues.
- `flutter test`: PASS, 95 tests.
- Android lint, release APK, and debug APK: recorded after final build in the handoff.
- Backend duplicate protection remains `(NIK, ActivityId)` and XP remains server-calculated.
- Backend activity-source behavior was not changed because Sprint 4 requires explicit approval before that compatibility change.

## Open release gates

- The required older/newer Android duration matrix, two-vendor matrix, background/lock tests, and route field matrix are incomplete.
- Physical sync idempotency evidence against the production sheet is still required even though local automated retry/duplicate tests pass.
- iOS build, foreground/background/lock validation, signing, and TestFlight checks require macOS and a representative iPhone.
- Android release currently uses the debug signing key. A production keystore and protected CI/local signing configuration are required.
- Store privacy/data-safety declarations require product-owner review before submission.

Production readiness is therefore **not declared**.

## Duration semantic note

The approved Sprint 3 UX/product addendum is authoritative: active duration starts when the run starts and resumes immediately when the user resumes; GPS reacquisition gates distance, not the active timer. This intentionally supersedes the older matrix sentence that said resume duration must wait for a new GPS baseline.
