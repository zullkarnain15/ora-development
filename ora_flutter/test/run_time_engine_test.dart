import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/domain/run_time_engine.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

RunSession _session({
  TrackingStatus status = TrackingStatus.running,
  int accumulated = 2000,
  int? anchor = 1000,
  int checkpoint = 4000,
  int bootEpoch = 100000,
}) => RunSession(
  sessionId: 'S1',
  ownerNik: '1001',
  nicknameSnapshot: 'RUNNER',
  divisionGuildSnapshot: 'OPS',
  status: status,
  policyVersion: 2,
  startEpochMillis: 100000,
  startMonotonicMillis: 0,
  bootEpochMillis: bootEpoch,
  activeAccumulatedMillis: accumulated,
  activeAnchorMonotonicMillis: anchor,
  lastCheckpointMonotonicMillis: checkpoint,
  distanceMeters: 100,
  acceptedPoints: 2,
  rejectedPoints: 0,
  createdAtMillis: 100000,
  updatedAtMillis: 104000,
);

NativeClockSnapshot _clock(int monotonic, {int bootEpoch = 100000}) =>
    NativeClockSnapshot(
      monotonicMillis: monotonic,
      epochMillis: bootEpoch + monotonic,
      bootEpochMillis: bootEpoch,
    );

void main() {
  test('RUNNING duration advances without another GPS callback', () {
    final run = _session();
    expect(RunTimeEngine.activeDurationAt(run, 6000, 100000), 7000);
    expect(RunTimeEngine.activeDurationAt(run, 11000, 100000), 12000);
  });

  test('delayed UI sample catches up from the monotonic anchor', () {
    final run = RunTimeEngine.enterRunning(
      _session(
        status: TrackingStatus.acquiringGps,
        accumulated: 3000,
        anchor: null,
      ),
      _clock(5000),
    );
    expect(RunTimeEngine.activeDurationAt(run, 35000, 100000), 33000);
  });

  test('acquisition is separate and does not add active duration', () {
    final acquiring = _session(
      status: TrackingStatus.acquiringGps,
      accumulated: 2500,
      anchor: null,
    );
    expect(RunTimeEngine.activeDurationAt(acquiring, 90000, 100000), 2500);
    expect(RunTimeEngine.sessionElapsedAt(acquiring, _clock(90000)), 90000);
  });

  test('pause freezes active time and resume starts a new anchor', () {
    final paused = RunTimeEngine.pause(_session(), _clock(6000));
    expect(paused.status, TrackingStatus.paused);
    expect(paused.activeAccumulatedMillis, 7000);
    expect(paused.activeAnchorMonotonicMillis, isNull);
    expect(RunTimeEngine.activeDurationAt(paused, 50000, 100000), 7000);
    final resumed = RunTimeEngine.enterRunning(paused, _clock(50000));
    expect(RunTimeEngine.activeDurationAt(resumed, 53000, 100000), 10000);
  });

  test('lock/deep sleep interval is included by elapsed realtime', () {
    expect(RunTimeEngine.activeDurationAt(_session(), 61000, 100000), 62000);
  });

  test('process recovery freezes at checkpoint and reacquires', () {
    final recovered = RunTimeEngine.recoverForReacquisition(
      _session(),
      _clock(20000),
    );
    expect(recovered.status, TrackingStatus.reacquiring);
    expect(recovered.activeAccumulatedMillis, 5000);
    expect(recovered.activeAnchorMonotonicMillis, isNull);
  });

  test('reboot boundary never reuses monotonic values from old boot', () {
    final run = _session();
    expect(RunTimeEngine.activeDurationAt(run, 20000, 500000), 5000);
    final recovered = RunTimeEngine.recoverForReacquisition(
      run,
      _clock(500, bootEpoch: 500000),
    );
    expect(recovered.activeAccumulatedMillis, 5000);
    expect(recovered.status, TrackingStatus.reacquiring);
  });
}
