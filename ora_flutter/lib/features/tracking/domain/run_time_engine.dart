import 'dart:math' as math;

import 'tracking_models.dart';

abstract interface class TrackingClock {
  Future<NativeClockSnapshot> snapshot();
}

abstract final class RunTimeEngine {
  static const bootEpochToleranceMillis = 5000;

  static bool sameBoot(int persistedBootEpoch, int currentBootEpoch) =>
      (persistedBootEpoch - currentBootEpoch).abs() <= bootEpochToleranceMillis;

  static int activeDurationAt(
    RunSession session,
    int nowMonotonicMillis,
    int currentBootEpochMillis,
  ) {
    final anchor = session.activeAnchorMonotonicMillis;
    if (session.status != TrackingStatus.running || anchor == null) {
      return session.activeAccumulatedMillis;
    }
    if (!sameBoot(session.bootEpochMillis, currentBootEpochMillis)) {
      return session.activeAccumulatedMillis +
          math.max(0, session.lastCheckpointMonotonicMillis - anchor);
    }
    return session.activeAccumulatedMillis +
        math.max(0, nowMonotonicMillis - anchor);
  }

  static int sessionElapsedAt(RunSession session, NativeClockSnapshot now) {
    if (sameBoot(session.bootEpochMillis, now.bootEpochMillis)) {
      return math.max(0, now.monotonicMillis - session.startMonotonicMillis);
    }
    return math.max(
      0,
      (session.endEpochMillis ?? now.epochMillis) - session.startEpochMillis,
    );
  }

  static RunSession enterRunning(RunSession session, NativeClockSnapshot now) =>
      session.copyWith(
        status: TrackingStatus.running,
        activeAnchorMonotonicMillis: now.monotonicMillis,
        lastCheckpointMonotonicMillis: now.monotonicMillis,
        updatedAtMillis: now.epochMillis,
      );

  static RunSession pause(RunSession session, NativeClockSnapshot now) =>
      session.copyWith(
        status: TrackingStatus.paused,
        activeAccumulatedMillis: activeDurationAt(
          session,
          now.monotonicMillis,
          now.bootEpochMillis,
        ),
        clearActiveAnchor: true,
        lastCheckpointMonotonicMillis: now.monotonicMillis,
        updatedAtMillis: now.epochMillis,
      );

  static RunSession checkpoint(RunSession session, NativeClockSnapshot now) =>
      session.copyWith(
        lastCheckpointMonotonicMillis: now.monotonicMillis,
        updatedAtMillis: now.epochMillis,
      );

  /// Recovery never joins a pre-interruption segment to a new GPS segment.
  static RunSession recoverForReacquisition(
    RunSession session,
    NativeClockSnapshot now,
  ) {
    final accumulated = activeDurationAt(
      session,
      session.lastCheckpointMonotonicMillis,
      now.bootEpochMillis,
    );
    return session.copyWith(
      status: TrackingStatus.reacquiring,
      activeAccumulatedMillis: accumulated,
      clearActiveAnchor: true,
      lastCheckpointMonotonicMillis: now.monotonicMillis,
      updatedAtMillis: now.epochMillis,
    );
  }
}
