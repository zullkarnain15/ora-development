# Sprint 3 Dependency Decision

Date: 2026-08-14  
Decision: **no additional Flutter or native third-party dependency**

## Chosen implementation

- Pure Dart owns GPS policy, state transitions, distance, pace, clocks, persistence, finalization, and recovery.
- Existing `sqflite 2.4.3` and `path 1.9.1` remain the only tracking-related runtime packages.
- Android uses platform `LocationManager`, `Service`, `SystemClock.elapsedRealtime`, notification APIs, and a versioned Flutter MethodChannel/EventChannel bridge.
- iOS uses Core Location, `ProcessInfo.systemUptime`, Background Modes location, and the same normalized bridge contract.

## Reason

The Sprint requires explicit control over precise/approximate permission diagnosis, Android location foreground-service lifecycle, monotonic provider timestamps, notification actions, recovery evidence, and iOS force-quit boundaries. A direct platform adapter keeps those behaviors visible and testable while leaving all product policy in pure Dart.

No GPS threshold was changed to compensate for device behavior, and no timer/location package was introduced to obscure the root cause.

## Trade-offs

- Native adapter code must be compiled and physically tested on both platforms.
- Android uses framework GPS/network providers rather than Google Play Services fused location; vendor/API coverage is therefore mandatory before release.
- iOS compilation cannot be validated on Windows and remains a macOS gate.
