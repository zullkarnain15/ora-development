# Sprint 3 Device Test Matrix

Date: 2026-08-14  
Status: **incomplete - required before Sprint 3 release acceptance**

## Evidence table

| Band | Manufacturer / model | OS / API | Target SDK | Security patch | Location / grant | Notification | Battery / bucket | App state | Result |
|---|---|---:|---:|---|---|---|---|---|---|
| API 26-30 | Not available | - | 36 | - | Precise, approximate/denied variants pending | Pending | Pending | Foreground/background/lock pending | NOT RUN |
| API 31-33 | Not available | - | 36 | - | Precise, Approximate, Only this time, denied pending | Pending | Pending | Foreground/background/lock pending | NOT RUN |
| API 34-35 | Not available | - | 36 | - | Precise and denied pending | Pending | Pending | Foreground/background/lock pending | NOT RUN |
| API 36+ | Samsung SM-S731B | Android 16 / API 36 | 36 | 2026-07-05 | Location ON; precise foreground granted | Granted | Saver OFF; standby bucket active (10) | Foreground, screen unlocked | Install/start PASS; location FGS type PASS; ongoing notification/actions PASS; callbacks arrived; indoor accuracy `POOR`, therefore baseline and physical advancing duration NOT VERIFIED |
| Second vendor | Not available | - | 36 | - | Pending | Pending | Pending | Pending | NOT RUN |

## Required test for every remaining device

Record the values before the run:

- manufacturer, model, Android release, API level, security patch, and ORA target SDK;
- location services ON/OFF;
- Precise/Approximate/Only this time/denied state;
- notification permission;
- battery saver and vendor battery optimization;
- app foreground/background state and screen locked/unlocked.

Run the following cases:

1. Start ORA while visible and confirm the location foreground-service notification appears.
2. With Precise enabled, go outdoors and wait for an accepted baseline (`RUNNING`, not `ACQUIRING`).
3. After `RUNNING`, stand still for at least 15 seconds. Active duration must continue without a GPS callback every second.
4. Lock the screen for at least 30 seconds, unlock, and confirm duration catches up from monotonic time.
5. Pause for at least 15 seconds. Active duration must freeze.
6. Resume. ORA must show `REACQUIRING` and start a new active anchor only after a fresh baseline.
7. Background and foreground the app while tracking; the notification must remain and duration must catch up.
8. Force-stop/process-interrupt once, relaunch, and verify Resume, End & Save, and confirmed Discard recovery choices. Do not join distance across the interruption.
9. Finish twice/rapidly tap controls; only one local activity may exist and no foreground service may remain.
10. Repeat once with Approximate and once denied. ORA must give a precise actionable error and must not display `RUNNING`.

## Acceptance rule

The duration blocker closes only after:

- an older API 26-30 device retains working behavior;
- API 31-33 permission variants are covered;
- API 34-35 foreground-service behavior is covered;
- the Samsung API 36 device (or the originally failing new phone) reaches a real baseline and shows advancing active duration;
- at least one second Android vendor passes;
- failures include the diagnostic timeline without raw coordinates.
