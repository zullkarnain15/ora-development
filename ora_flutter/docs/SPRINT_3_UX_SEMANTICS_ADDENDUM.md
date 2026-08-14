# Sprint 3 — GPS, Duration, and Back Navigation Addendum

Date: 2026-08-14

This product decision supersedes the earlier GPS-acquisition timer behavior.

## Run preparation

- Opening RUN begins a foreground-only GPS preview after precise-location permission is available.
- The screen shows a 20-second `SEARCHING FOR GPS` countdown.
- `START ADVENTURE` is enabled only after a fresh fix passes the GPS quality policy.
- If no acceptable fix is found in 20 seconds, the spinner stops and offers
  `START ANYWAY` or `CANCEL RUN`.
- `START ANYWAY` is available only when precise-location permission and device
  location services are valid. Active duration starts immediately, while
  distance remains at zero until an acceptable GPS baseline arrives.
- The preview stops when RUN is left or the application goes to the background. It does not create a run or foreground service.

## Active duration

- Active duration begins immediately when the user presses START.
- Only an explicit PAUSE freezes active duration.
- Weak, missing, or temporarily unavailable GPS pauses distance accumulation only; active duration continues.
- Resume and recovery resume restart the active clock immediately while distance waits for a fresh baseline.

## Android system Back

- Back from Settings closes Settings.
- Back from Quest, RUN, Guild, or You returns to Home first.
- On Home, the first Back shows `PRESS BACK AGAIN TO EXIT` for two seconds.
- A second Back within that window exits the application.
- Exiting or returning Home does not stop an active run; native foreground tracking remains authoritative.

## iOS verification status

The equivalent Core Location preview contract is implemented and source-checked. A physical iOS build and runtime verification remains deferred until macOS/Xcode hardware is available.
