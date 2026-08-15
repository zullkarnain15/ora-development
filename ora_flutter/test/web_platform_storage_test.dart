import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:ora_flutter/features/activity/data/web_activity_store.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/auth/data/web_session_store.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

class _FakeWebSessionStorage implements WebSessionStorage {
  final Map<String, String> persistent = {};
  final Map<String, String> perTab = {};

  @override
  String? readPersistent(String key) => persistent[key];

  @override
  String? readPerTab(String key) => perTab[key];

  @override
  void writePersistent(String key, String value) => persistent[key] = value;

  @override
  void removePersistent(String key) => persistent.remove(key);

  @override
  void removePerTab(String key) => perTab.remove(key);
}

void main() {
  test(
    'Web activity store persists, isolates owners, and syncs safely',
    () async {
      final databaseName =
          'ora_web_test_${DateTime.now().microsecondsSinceEpoch}';
      final factory = newIdbFactoryMemory();
      final activity = FinalActivity(
        activityId: 'A1',
        ownerNik: '1001',
        nicknameSnapshot: 'RUNNER',
        divisionGuildSnapshot: 'OPS',
        startDateTimeMillis: 1000,
        endDateTimeMillis: 61000,
        distanceMeters: 1000,
        activeDurationMillis: 60000,
        averagePaceSecondsPerKm: 60,
        createdAtMillis: 61000,
        syncStatus: ActivitySyncStatus.pending,
      );

      final first = WebActivityStore(
        factory: factory,
        databaseName: databaseName,
      );
      expect(await first.insert(activity), isTrue);

      final reloaded = WebActivityStore(
        factory: factory,
        databaseName: databaseName,
      );
      expect((await reloaded.newestFirst('1001')).single.activityId, 'A1');
      expect((await reloaded.dueSync('1001', 0)).single.activityId, 'A1');

      final otherOwner = FinalActivity(
        activityId: 'B1',
        ownerNik: '2002',
        nicknameSnapshot: 'OTHER',
        divisionGuildSnapshot: 'SALES',
        startDateTimeMillis: 2000,
        endDateTimeMillis: 62000,
        distanceMeters: 500,
        activeDurationMillis: 60000,
        averagePaceSecondsPerKm: 120,
        createdAtMillis: 62000,
        syncStatus: ActivitySyncStatus.pending,
      );
      expect(await reloaded.insert(otherOwner), isTrue);
      expect(await reloaded.insert(otherOwner), isFalse);
      expect(
        (await reloaded.newestFirst('1001')).map((item) => item.activityId),
        ['A1'],
      );
      expect(
        (await reloaded.newestFirst('2002')).map((item) => item.activityId),
        ['B1'],
      );

      final firstPayload = (await reloaded.dueSync('1001', 0)).single.payload;
      final queueId = 'activity_${activity.activityId}';
      expect(await reloaded.beginSync(queueId, '2002', 100), isFalse);
      expect(await reloaded.beginSync(queueId, '1001', 100), isTrue);
      await reloaded.failSync(
        queueId,
        '1001',
        nowMillis: 100,
        nextAttemptAtMillis: 200,
        errorCode: 'OFFLINE',
      );
      expect(await reloaded.dueSync('1001', 199), isEmpty);

      final afterReload = WebActivityStore(
        factory: factory,
        databaseName: databaseName,
      );
      final retry = (await afterReload.dueSync('1001', 200)).single;
      expect(retry.payload.encode(), firstPayload.encode());
      expect(
        await afterReload.acknowledgeSync(
          retry.queueId,
          retry.activityId,
          '1001',
          serverStatus: 'DUPLICATE',
          acknowledgedAtMillis: 300,
        ),
        isTrue,
      );
      expect(await afterReload.pending('1001'), isEmpty);
      expect(
        (await afterReload.newestFirst('1001')).single.syncStatus,
        ActivitySyncStatus.synced,
      );
    },
  );

  test('Web local session survives a new store and clears cleanly', () async {
    final storage = _FakeWebSessionStorage();
    final first = WebSessionStore(storage: storage);
    final session = UserSession(
      sessionToken: 'browser-session-fixture',
      nik: '1001',
      nickname: 'RUNNER',
      divisionGuild: 'OPS',
      status: 'ACTIVE',
      expiresAt: DateTime.utc(2030),
    );
    await first.save(session);
    expect((await WebSessionStore(storage: storage).load())?.nik, '1001');
    await first.clear();
    expect(await WebSessionStore(storage: storage).load(), isNull);
    expect(storage.persistent, isEmpty);
    expect(storage.perTab, isEmpty);
  });

  test('Web session migrates legacy per-tab storage', () async {
    final storage = _FakeWebSessionStorage();
    const key = WebSessionStore.storageKey;
    storage.perTab[key] =
        '{"sessionToken":"fixture","nik":"1001","nickname":"RUNNER",'
        '"divisionGuild":"OPS","status":"ACTIVE",'
        '"expiresAt":"2030-01-01T00:00:00.000Z"}';
    expect((await WebSessionStore(storage: storage).load())?.nik, '1001');
    expect(storage.persistent[key], isNotNull);
    expect(storage.perTab[key], isNull);
  });

  test('Web run survives reload and finalization is idempotent', () async {
    final databaseName = 'ora_run_${DateTime.now().microsecondsSinceEpoch}';
    final factory = newIdbFactoryMemory();
    final store = WebActivityStore(
      factory: factory,
      databaseName: databaseName,
    );
    final run = RunSession(
      sessionId: 'S1',
      ownerNik: '1001',
      nicknameSnapshot: 'RUNNER',
      divisionGuildSnapshot: 'OPS',
      status: TrackingStatus.running,
      policyVersion: 3,
      startEpochMillis: 100000,
      startMonotonicMillis: 1000,
      bootEpochMillis: 99000,
      activeAccumulatedMillis: 60000,
      activeAnchorMonotonicMillis: 1000,
      lastCheckpointMonotonicMillis: 61000,
      distanceMeters: 100,
      acceptedPoints: 1,
      rejectedPoints: 0,
      createdAtMillis: 100000,
      updatedAtMillis: 160000,
    );
    const event = RunEvent(
      eventId: 'E1',
      sessionId: 'S1',
      type: 'START',
      monotonicMillis: 1000,
      epochMillis: 100000,
    );
    await store.createRun(run, event);
    await store.recordPointDecision(
      run,
      const PersistedPointDecision(
        sessionId: 'S1',
        sample: RawLocationSample(
          latitude: -6.2,
          longitude: 106.8,
          accuracyMeters: 8,
          providerMonotonicMillis: 2000,
          receivedMonotonicMillis: 2000,
          epochMillis: 101000,
          sequence: 1,
        ),
        decision: LocationDecision(
          type: LocationDecisionType.accepted,
          segmentMeters: 100,
        ),
      ),
    );

    final reloaded = WebActivityStore(
      factory: factory,
      databaseName: databaseName,
    );
    expect((await reloaded.recoverableRun('1001'))?.sessionId, 'S1');
    expect(await reloaded.recoverableRun('2002'), isNull);

    final ended = run.copyWith(
      status: TrackingStatus.finalizing,
      endEpochMillis: 160000,
      clearActiveAnchor: true,
    );
    await reloaded.updateRun(
      ended,
      const RunEvent(
        eventId: 'E2',
        sessionId: 'S1',
        type: 'FINISH',
        monotonicMillis: 61000,
        epochMillis: 160000,
      ),
    );
    final first = await reloaded.finalizeRun(ended);
    final duplicate = await reloaded.finalizeRun(ended);
    expect(first.activityId, 'run_S1');
    expect(duplicate.activityId, first.activityId);
    expect(first.distanceMeters, 100);
    expect((await reloaded.dueSync('1001', 0)).length, 1);
    expect((await reloaded.acceptedRoute(first.activityId, '1001')).length, 1);
    expect(await reloaded.recoverableRun('1001'), isNull);
  });
}
