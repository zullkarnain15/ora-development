import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

RunSession _run({TrackingStatus status = TrackingStatus.running}) => RunSession(
  sessionId: 'S1',
  ownerNik: '1001',
  nicknameSnapshot: 'RUNNER',
  divisionGuildSnapshot: 'OPS',
  status: status,
  policyVersion: 2,
  startEpochMillis: 1000,
  endEpochMillis: 11000,
  startMonotonicMillis: 10,
  bootEpochMillis: 990,
  activeAccumulatedMillis: 6000,
  activeAnchorMonotonicMillis: status == TrackingStatus.running ? 20 : null,
  lastCheckpointMonotonicMillis: 6000,
  distanceMeters: 999,
  acceptedPoints: 2,
  rejectedPoints: 1,
  createdAtMillis: 1000,
  updatedAtMillis: 11000,
);

RunEvent _event(String id) => RunEvent(
  eventId: id,
  sessionId: 'S1',
  type: 'TEST',
  monotonicMillis: 10,
  epochMillis: 1000,
);

PersistedPointDecision _point({
  required int sequence,
  required LocationDecision decision,
}) => PersistedPointDecision(
  sessionId: 'S1',
  sample: RawLocationSample(
    latitude: -6.2,
    longitude: 106.8 + sequence / 10000,
    accuracyMeters: 5,
    providerMonotonicMillis: sequence * 1000,
    receivedMonotonicMillis: sequence * 1000,
    epochMillis: sequence * 1000,
    sequence: sequence,
  ),
  decision: decision,
);

void main() {
  test(
    'point decisions and critical session counters persist together',
    () async {
      final store = MemoryActivityStore();
      final run = _run();
      await store.createRun(run, _event('E1'));
      final updated = run.copyWith(distanceMeters: 12, acceptedPoints: 2);
      await store.recordPointDecision(
        updated,
        _point(
          sequence: 1,
          decision: const LocationDecision(
            type: LocationDecisionType.accepted,
            segmentMeters: 12,
          ),
        ),
      );
      expect((await store.recoverableRun('1001'))?.distanceMeters, 12);
    },
  );

  test('rejected/raw points add no reconciled final distance', () async {
    final store = MemoryActivityStore();
    final run = _run();
    await store.createRun(run, _event('E1'));
    await store.recordPointDecision(
      run,
      _point(
        sequence: 1,
        decision: const LocationDecision(
          type: LocationDecisionType.rejected,
          reason: LocationRejectReason.poorAccuracy,
          segmentMeters: 500,
        ),
      ),
    );
    final saved = await store.finalizeRun(run);
    expect(saved.distanceMeters, 0);
  });

  test('finalization is idempotent and creates exactly one activity', () async {
    final store = MemoryActivityStore();
    final run = _run(status: TrackingStatus.finalizing);
    await store.createRun(run, _event('E1'));
    await store.recordPointDecision(
      run,
      _point(
        sequence: 1,
        decision: const LocationDecision(
          type: LocationDecisionType.accepted,
          segmentMeters: 42,
        ),
      ),
    );
    final first = await store.finalizeRun(run);
    final second = await store.finalizeRun(run);
    expect(second.activityId, first.activityId);
    expect((await store.newestFirst('1001')), hasLength(1));
    expect(first.distanceMeters, 42);
  });

  test('recovery is owner scoped and confirmed discard removes it', () async {
    final store = MemoryActivityStore();
    await store.createRun(_run(), _event('E1'));
    expect(await store.recoverableRun('2002'), isNull);
    expect(await store.recoverableRun('1001'), isNotNull);
    await store.discardRun('S1', '2002');
    expect(await store.recoverableRun('1001'), isNotNull);
    await store.discardRun('S1', '1001');
    expect(await store.recoverableRun('1001'), isNull);
  });
}
