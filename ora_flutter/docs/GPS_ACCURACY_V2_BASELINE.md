# ORA GPS Accuracy V2 baseline

## Golden Android field reference

This result is a regression reference, never an algorithm input or calibration
factor.

| Device | Distance | Duration | Pace |
| --- | ---: | ---: | ---: |
| COROS GPS watch | 11.63 km | 1:27:28 | 7:31/km |
| ORA Android | 11.62 km | 1:27:37 | 7:33/km |

The shared final reconciler must be a no-op on a clean track. No multiplier,
road snapping, map matching, or Strava/COROS-specific correction is allowed.

## Protected Android policy

GPS collection remains one callback request per second with a native 2 m
minimum displacement. The Dart integrator remains:

- maximum horizontal accuracy: 30 m;
- minimum segment: 2 m;
- maximum jitter threshold: 5 m;
- accuracy jitter factor: 0.25;
- maximum implied running speed: 12 m/s;
- maximum location age: 15 s;
- re-entry gap: 10 s;
- one continuity confirmation after an implausible jump;
- stale, future, duplicate timestamp, invalid coordinate, missing accuracy,
  poor accuracy, duplicate coordinate, jitter, and implausible-speed rejection;
- pause clears the anchor and Resume requires a fresh baseline;
- distance is the sum of accepted geodesic segments only.

V2 does not change any of those values. It only separates minimum-segment and
jitter diagnostic labels without changing the acceptance result.

## Web policy audit

The Web policy remains unchanged pending field diagnostics:

- maximum horizontal accuracy: 35 m;
- minimum segment: 3 m;
- maximum jitter threshold: 8 m;
- accuracy jitter factor: 0.35;
- maximum implied running speed: 10 m/s;
- maximum location age: 30 s;
- re-entry gap: 15 s.

The 0.72 km PWA result versus 0.85 km Strava suggests missing accepted distance,
but the existing field result does not identify which rejection category or
callback gap caused it. Thresholds must not be relaxed until the new summary is
captured during another field run.

## GPS soak

Android uses a light profile: three consecutive samples, at least 3 seconds,
all at 20 m accuracy or better, no sample worse than 30 m, and at most 35 m
spread. Web uses five consecutive samples, at least 5 seconds, all at 20 m or
better, no sample worse than 35 m, and at most 45 m spread. Both time out after
20 seconds. A timeout becomes degraded-ready only when multiple recent samples
remain usable; otherwise the existing explicit Start Anyway path remains.

Soak points never enter the run route. Start resets the live integrator and the
first post-Start fix becomes a fresh anchor.

## Finish reconciliation and privacy

Reconciliation processes each baseline/re-entry segment independently. It can
remove only a high-confidence poor-accuracy lateral spike or a high-confidence
stationary poor-accuracy drift cluster. Real corners, curves, U-turns,
switchbacks, out-and-back routes, slow movement, and pause relocation are
protected. If the proposed correction exceeds 10% or 200 m, it is discarded
and flagged `RECONCILIATION_SUSPICIOUS`.

Raw coordinates remain local. Debug summaries contain counts, accuracy bands,
callback timing, integrated/final distance, soak metrics, and flags—but no
coordinates, NIK, PIN, session token, or uploaded route.
