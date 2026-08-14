# Sprint 4 Device and Field Test Matrix

Date: 2026-08-14  
Status: **incomplete - required before production release**

## Device evidence

| Band | Device / vendor | OS / API | Coverage | Result |
|---|---|---:|---|---|
| Older Android (API 26-30) | Not available | - | Duration, background, lock, recovery | NOT RUN |
| Android 12/13 (API 31-33) | Not available | - | Precise, approximate, denied, notification | NOT RUN |
| Android 14/15 (API 34-35) | Not available | - | Location FGS restrictions, background, lock | NOT RUN |
| Current Android | Samsung SM-S731B | Android 16 / API 36 | Install/start, location FGS, ongoing notification/actions and callbacks passed. Indoor accuracy stayed poor, so outdoor duration/distance acceptance is pending. | PARTIAL |
| Second Android vendor | Not available | - | Full duration and background flow | NOT RUN |
| iPhone | macOS/device not available | - | Build, foreground/background/lock, recovery | NOT RUN |

## Field route matrix

| Scenario | Required evidence | Result |
|---|---|---|
| Open-sky straight route | accepted/rejected counts, accuracy, distance drift | NOT RUN |
| Known-distance loop/stadium | accepted distance vs reference | NOT RUN |
| Urban canyon | spike/rejection evidence | NOT RUN |
| Tunnel/underpass | gap and re-entry boundary | NOT RUN |
| Stationary 2-3 minutes | distance creep and duration drift | NOT RUN |
| Pause then move 200-300 m | no bridged distance | NOT RUN |
| Poor GPS start | waiting/timeout/start-anyway behavior | NOT RUN |
| Internet disabled | local finish, pending queue, later ACK | NOT RUN |
| Process interruption | recovery, no duration/distance duplication | NOT RUN |
| Lock/background | timer catch-up and native tracking | NOT RUN |
| Battery saver/low battery | continuity and battery delta | NOT RUN |

For every execution record policy version, model/vendor/API, permission mode, battery state, accepted/rejected counts by reason, accuracy distribution, maximum gap, recovery count, reference-versus-accepted distance, battery delta, duration drift, and PASS/FAIL.

## Sync idempotency field case

1. Finish offline and record the stable ActivityId.
2. Reconnect with a deliberately interrupted first upload.
3. Retry the same queued item until the backend returns `SAVED` or `DUPLICATE`.
4. Confirm one row only for `(NIK, ActivityId)`, one XP contribution, durable local ACK, and refreshed stats/Quest progress.

Automated stable-payload and `DUPLICATE` tests do not replace this production-sheet evidence.
