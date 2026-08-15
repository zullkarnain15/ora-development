import 'package:idb_shim/idb_browser.dart';

import '../../tracking/domain/tracking_models.dart';
import '../../tracking/domain/location_engine.dart';
import '../domain/activity_sync.dart';
import '../domain/final_activity.dart';
import 'activity_store.dart';

/// Browser implementation backed by IndexedDB, including durable run recovery.
class WebActivityStore implements ActivityStore {
  WebActivityStore({IdbFactory? factory, this.databaseName = 'ora_web'})
    : _factory = factory ?? getIdbFactory()!;

  static const _activities = 'activities';
  static const _syncQueue = 'sync_queue';
  static const _runSessions = 'run_sessions';
  static const _locationPoints = 'location_points';
  static const _runEvents = 'run_events';
  final IdbFactory _factory;
  final String databaseName;
  Database? _database;

  Future<Database> get _db async => _database ??= await _factory.open(
    databaseName,
    version: 2,
    onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains(_activities)) {
        db.createObjectStore(_activities, keyPath: 'activityId');
      }
      if (!db.objectStoreNames.contains(_syncQueue)) {
        db.createObjectStore(_syncQueue, keyPath: 'queueId');
      }
      if (!db.objectStoreNames.contains(_runSessions)) {
        db.createObjectStore(_runSessions, keyPath: 'sessionId');
      }
      if (!db.objectStoreNames.contains(_locationPoints)) {
        db.createObjectStore(_locationPoints, keyPath: 'pointKey');
      }
      if (!db.objectStoreNames.contains(_runEvents)) {
        db.createObjectStore(_runEvents, keyPath: 'eventId');
      }
    },
  );

  @override
  Future<bool> insert(FinalActivity activity) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _activities,
      _syncQueue,
    ], idbModeReadWrite);
    final activities = transaction.objectStore(_activities);
    if (await activities.getObject(activity.activityId) != null) {
      await transaction.completed;
      return false;
    }
    final reason = activitySyncIneligibilityReason(activity);
    final stored = reason == null
        ? activity
        : activity.withSyncStatus(ActivitySyncStatus.notEligible);
    await activities.add(stored.toMap());
    if (reason == null &&
        (stored.syncStatus == ActivitySyncStatus.pending ||
            stored.syncStatus == ActivitySyncStatus.localOnly)) {
      await transaction.objectStore(_syncQueue).put(_queueMap(stored));
    }
    await transaction.completed;
    return true;
  }

  @override
  Future<List<FinalActivity>> pending(String ownerNik) async =>
      (await newestFirst(ownerNik))
          .where(
            (item) =>
                item.syncStatus == ActivitySyncStatus.pending ||
                item.syncStatus == ActivitySyncStatus.localOnly,
          )
          .toList(growable: false);

  @override
  Future<bool> markSynced(String activityId, String ownerNik) =>
      acknowledgeSync(
        'activity_$activityId',
        activityId,
        ownerNik,
        serverStatus: 'LEGACY_ACK',
        acknowledgedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

  @override
  Future<List<SyncQueueEntry>> dueSync(
    String ownerNik,
    int nowMillis, {
    bool force = false,
  }) async {
    final rows = await _all(_syncQueue);
    final entries =
        rows
            .map(_syncEntry)
            .where(
              (entry) =>
                  entry.ownerNik == ownerNik &&
                  entry.state != SyncQueueState.acknowledged &&
                  entry.state != SyncQueueState.notEligible &&
                  (force || entry.nextAttemptAtMillis <= nowMillis),
            )
            .toList()
          ..sort((a, b) => a.createdAtMillis.compareTo(b.createdAtMillis));
    return List.unmodifiable(entries);
  }

  @override
  Future<bool> beginSync(String queueId, String ownerNik, int nowMillis) async {
    final db = await _db;
    final transaction = db.transaction(_syncQueue, idbModeReadWrite);
    final store = transaction.objectStore(_syncQueue);
    final row = _mapOrNull(await store.getObject(queueId));
    if (row == null ||
        row['ownerNik'] != ownerNik ||
        row['state'] == SyncQueueState.acknowledged.value ||
        row['state'] == SyncQueueState.notEligible.value) {
      await transaction.completed;
      return false;
    }
    row['state'] = SyncQueueState.uploading.value;
    row['retryCount'] = ((row['retryCount'] as num?)?.toInt() ?? 0) + 1;
    row['lastAttemptAtMillis'] = nowMillis;
    row['updatedAtMillis'] = nowMillis;
    row['lastErrorCode'] = null;
    await store.put(row);
    await transaction.completed;
    return true;
  }

  @override
  Future<void> failSync(
    String queueId,
    String ownerNik, {
    required int nowMillis,
    required int nextAttemptAtMillis,
    required String errorCode,
  }) async {
    await _updateQueue(queueId, ownerNik, (row) {
      if (row['state'] != SyncQueueState.uploading.value) return false;
      row['state'] = SyncQueueState.retry.value;
      row['nextAttemptAtMillis'] = nextAttemptAtMillis;
      row['lastErrorCode'] = errorCode;
      row['updatedAtMillis'] = nowMillis;
      return true;
    });
  }

  @override
  Future<bool> acknowledgeSync(
    String queueId,
    String activityId,
    String ownerNik, {
    required String serverStatus,
    required int acknowledgedAtMillis,
  }) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _activities,
      _syncQueue,
    ], idbModeReadWrite);
    final queueStore = transaction.objectStore(_syncQueue);
    final activityStore = transaction.objectStore(_activities);
    final queue = _mapOrNull(await queueStore.getObject(queueId));
    final activity = _mapOrNull(await activityStore.getObject(activityId));
    if (queue == null ||
        activity == null ||
        queue['activityId'] != activityId ||
        queue['ownerNik'] != ownerNik ||
        activity['ownerNik'] != ownerNik) {
      await transaction.completed;
      return false;
    }
    queue['state'] = SyncQueueState.acknowledged.value;
    queue['serverStatus'] = serverStatus;
    queue['serverAckAtMillis'] = acknowledgedAtMillis;
    queue['updatedAtMillis'] = acknowledgedAtMillis;
    queue['lastErrorCode'] = null;
    activity['syncStatus'] = ActivitySyncStatus.synced.value;
    await queueStore.put(queue);
    await activityStore.put(activity);
    await transaction.completed;
    return true;
  }

  @override
  Future<bool> markSyncNotEligible(
    String queueId,
    String activityId,
    String ownerNik, {
    required String reason,
    required int markedAtMillis,
  }) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _activities,
      _syncQueue,
    ], idbModeReadWrite);
    final queueStore = transaction.objectStore(_syncQueue);
    final activityStore = transaction.objectStore(_activities);
    final queue = _mapOrNull(await queueStore.getObject(queueId));
    final activity = _mapOrNull(await activityStore.getObject(activityId));
    if (queue == null ||
        activity == null ||
        queue['activityId'] != activityId ||
        queue['ownerNik'] != ownerNik ||
        activity['ownerNik'] != ownerNik) {
      await transaction.completed;
      return false;
    }
    queue['state'] = SyncQueueState.notEligible.value;
    queue['updatedAtMillis'] = markedAtMillis;
    queue['lastErrorCode'] = reason;
    activity['syncStatus'] = ActivitySyncStatus.notEligible.value;
    await queueStore.put(queue);
    await activityStore.put(activity);
    await transaction.completed;
    return true;
  }

  @override
  Future<bool> deleteNotEligible(String activityId, String ownerNik) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _activities,
      _syncQueue,
      _runSessions,
      _locationPoints,
      _runEvents,
    ], idbModeReadWrite);
    final activities = transaction.objectStore(_activities);
    final activity = _mapOrNull(await activities.getObject(activityId));
    if (activity == null ||
        activity['ownerNik'] != ownerNik ||
        activity['syncStatus'] != ActivitySyncStatus.notEligible.value) {
      await transaction.completed;
      return false;
    }
    final runs = transaction.objectStore(_runSessions);
    for (final value in await runs.getAll()) {
      final run = _map(value);
      if (run['ownerNik'] == ownerNik && run['finalActivityId'] == activityId) {
        final sessionId = run['sessionId']! as String;
        await _deleteSessionRows(
          transaction.objectStore(_locationPoints),
          sessionId,
        );
        await _deleteSessionRows(
          transaction.objectStore(_runEvents),
          sessionId,
        );
        await runs.delete(sessionId);
      }
    }
    await activities.delete(activityId);
    await transaction.objectStore(_syncQueue).delete('activity_$activityId');
    await transaction.completed;
    return true;
  }

  @override
  Future<List<ActivityRoutePoint>> acceptedRoute(
    String activityId,
    String ownerNik,
  ) async {
    final sessions = (await _all(_runSessions)).where(
      (row) =>
          row['ownerNik'] == ownerNik && row['finalActivityId'] == activityId,
    );
    if (sessions.isEmpty) return const [];
    final sessionId = sessions.first['sessionId'];
    final points =
        (await _all(_locationPoints))
            .where(
              (row) =>
                  row['sessionId'] == sessionId &&
                  const {
                    'BASELINE',
                    'REENTRY_BASELINE',
                    'ACCEPTED',
                  }.contains(row['decision']),
            )
            .map(
              (row) => ActivityRoutePoint(
                latitude: (row['latitude']! as num).toDouble(),
                longitude: (row['longitude']! as num).toDouble(),
                sequence: (row['sequence']! as num).toInt(),
              ),
            )
            .toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return points;
  }

  @override
  Future<FinalActivity?> latest(String ownerNik) async {
    final values = await newestFirst(ownerNik);
    return values.isEmpty ? null : values.first;
  }

  @override
  Future<List<FinalActivity>> newestFirst(String ownerNik) async {
    final values = (await _all(_activities))
        .map(FinalActivity.fromMap)
        .where((item) => item.ownerNik == ownerNik)
        .toList();
    values.sort((a, b) {
      final byStart = b.startDateTimeMillis.compareTo(a.startDateTimeMillis);
      return byStart != 0
          ? byStart
          : b.createdAtMillis.compareTo(a.createdAtMillis);
    });
    return values;
  }

  @override
  Future<ActivityTotals> totals(String ownerNik) async {
    final values = await newestFirst(ownerNik);
    return ActivityTotals(
      activityCount: values.length,
      totalDistanceMeters: values.fold(
        0,
        (sum, item) => sum + item.distanceMeters,
      ),
      totalActiveDurationMillis: values.fold(
        0,
        (sum, item) => sum + item.activeDurationMillis,
      ),
    );
  }

  @override
  Future<void> createRun(RunSession session, RunEvent event) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _runSessions,
      _runEvents,
    ], idbModeReadWrite);
    final runs = transaction.objectStore(_runSessions);
    if (await runs.getObject(session.sessionId) != null) {
      await transaction.completed;
      throw StateError('Run session already exists.');
    }
    await runs.add(session.toMap());
    await transaction.objectStore(_runEvents).put(event.toMap());
    await transaction.completed;
  }

  @override
  Future<void> updateRun(RunSession session, RunEvent event) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _runSessions,
      _runEvents,
    ], idbModeReadWrite);
    final runs = transaction.objectStore(_runSessions);
    final current = _mapOrNull(await runs.getObject(session.sessionId));
    if (current == null || current['ownerNik'] != session.ownerNik) {
      await transaction.completed;
      throw StateError('Run session was not found.');
    }
    await runs.put(session.toMap());
    await transaction.objectStore(_runEvents).put(event.toMap());
    await transaction.completed;
  }

  @override
  Future<void> recordPointDecision(
    RunSession session,
    PersistedPointDecision point,
  ) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _runSessions,
      _locationPoints,
    ], idbModeReadWrite);
    final runs = transaction.objectStore(_runSessions);
    final current = _mapOrNull(await runs.getObject(session.sessionId));
    if (current == null || current['ownerNik'] != session.ownerNik) {
      await transaction.completed;
      throw StateError('Run session was not found.');
    }
    final row = point.toMap();
    row['pointKey'] = '${point.sessionId}_${point.sample.sequence}';
    await transaction.objectStore(_locationPoints).put(row);
    await runs.put(session.toMap());
    await transaction.completed;
  }

  @override
  Future<RunSession?> recoverableRun(String ownerNik) async {
    final sessions =
        (await _all(_runSessions))
            .where(
              (row) =>
                  row['ownerNik'] == ownerNik &&
                  !const {'IDLE', 'FINISHED', 'ERROR'}.contains(row['status']),
            )
            .map(RunSession.fromMap)
            .toList()
          ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    return sessions.isEmpty ? null : sessions.first;
  }

  @override
  Future<FinalActivity> finalizeRun(RunSession session) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _runSessions,
      _locationPoints,
      _activities,
      _syncQueue,
    ], idbModeReadWrite);
    final runs = transaction.objectStore(_runSessions);
    final activities = transaction.objectStore(_activities);
    final currentMap = _mapOrNull(await runs.getObject(session.sessionId));
    if (currentMap == null || currentMap['ownerNik'] != session.ownerNik) {
      await transaction.completed;
      throw StateError('Run session was not found.');
    }
    final current = RunSession.fromMap(currentMap);
    final existingId = current.finalActivityId;
    if (existingId != null) {
      final existing = _mapOrNull(await activities.getObject(existingId));
      await transaction.completed;
      if (existing != null) return FinalActivity.fromMap(existing);
    }

    final pointRows = (await transaction.objectStore(_locationPoints).getAll())
        .map(_map);
    final reconciledDistance = pointRows
        .where(
          (row) =>
              row['sessionId'] == session.sessionId &&
              row['decision'] == LocationDecisionType.accepted.value,
        )
        .fold<double>(
          0,
          (sum, row) => sum + ((row['segmentMeters'] as num?)?.toDouble() ?? 0),
        );
    final activityId = 'run_${session.sessionId}';
    final end = session.endEpochMillis ?? session.updatedAtMillis;
    final activity = FinalActivity(
      activityId: activityId,
      ownerNik: session.ownerNik,
      nicknameSnapshot: session.nicknameSnapshot,
      divisionGuildSnapshot: session.divisionGuildSnapshot,
      startDateTimeMillis: session.startEpochMillis,
      endDateTimeMillis: end,
      distanceMeters: reconciledDistance,
      activeDurationMillis: session.activeAccumulatedMillis,
      averagePaceSecondsPerKm: averagePaceSecondsPerKm(
        session.activeAccumulatedMillis,
        reconciledDistance,
      ),
      createdAtMillis: end,
      syncStatus: reconciledDistance > 0 && session.activeAccumulatedMillis > 0
          ? ActivitySyncStatus.pending
          : ActivitySyncStatus.notEligible,
    );
    await activities.put(activity.toMap());
    if (activity.syncStatus == ActivitySyncStatus.pending) {
      await transaction.objectStore(_syncQueue).put(_queueMap(activity));
    }
    await runs.put(
      session
          .copyWith(
            status: TrackingStatus.finished,
            distanceMeters: reconciledDistance,
            finalActivityId: activityId,
          )
          .toMap(),
    );
    await transaction.completed;
    return activity;
  }

  @override
  Future<void> discardRun(String sessionId, String ownerNik) async {
    final db = await _db;
    final transaction = db.transactionList(const [
      _runSessions,
      _locationPoints,
      _runEvents,
    ], idbModeReadWrite);
    final runs = transaction.objectStore(_runSessions);
    final run = _mapOrNull(await runs.getObject(sessionId));
    if (run == null ||
        run['ownerNik'] != ownerNik ||
        run['finalActivityId'] != null) {
      await transaction.completed;
      return;
    }
    await _deleteSessionRows(
      transaction.objectStore(_locationPoints),
      sessionId,
    );
    await _deleteSessionRows(transaction.objectStore(_runEvents), sessionId);
    await runs.delete(sessionId);
    await transaction.completed;
  }

  static Future<void> _deleteSessionRows(
    ObjectStore store,
    String sessionId,
  ) async {
    for (final value in await store.getAll()) {
      final row = _map(value);
      if (row['sessionId'] == sessionId) {
        final key = row['pointKey'] ?? row['eventId'];
        if (key != null) await store.delete(key);
      }
    }
  }

  Future<List<Map<String, Object?>>> _all(String storeName) async {
    final transaction = (await _db).transaction(storeName, idbModeReadOnly);
    final values = await transaction.objectStore(storeName).getAll();
    await transaction.completed;
    return values.map(_map).toList(growable: false);
  }

  Future<bool> _updateQueue(
    String queueId,
    String ownerNik,
    bool Function(Map<String, Object?> row) update,
  ) async {
    final transaction = (await _db).transaction(_syncQueue, idbModeReadWrite);
    final store = transaction.objectStore(_syncQueue);
    final row = _mapOrNull(await store.getObject(queueId));
    final changed = row != null && row['ownerNik'] == ownerNik && update(row);
    if (changed) await store.put(row);
    await transaction.completed;
    return changed;
  }

  static Map<String, Object?> _queueMap(FinalActivity activity) {
    final payload = ActivityPayloadMapper.mapV1(
      activity,
      deviceTime: DateTime.fromMillisecondsSinceEpoch(activity.createdAtMillis),
    );
    return {
      'queueId': 'activity_${activity.activityId}',
      'activityId': activity.activityId,
      'ownerNik': activity.ownerNik,
      'state': SyncQueueState.pending.value,
      'retryCount': 0,
      'payloadVersion': payload.version,
      'payloadJson': payload.encode(),
      'createdAtMillis': activity.createdAtMillis,
      'updatedAtMillis': activity.createdAtMillis,
      'nextAttemptAtMillis': 0,
    };
  }

  static SyncQueueEntry _syncEntry(Map<String, Object?> row) {
    final version = (row['payloadVersion'] as num?)?.toInt() ?? 1;
    return SyncQueueEntry(
      queueId: row['queueId']! as String,
      activityId: row['activityId']! as String,
      ownerNik: row['ownerNik']! as String,
      state: SyncQueueStateValue.parse(row['state'] as String?),
      retryCount: (row['retryCount'] as num?)?.toInt() ?? 0,
      payload: ActivityUploadPayload.decode(
        version,
        row['payloadJson']! as String,
      ),
      createdAtMillis: (row['createdAtMillis']! as num).toInt(),
      updatedAtMillis: (row['updatedAtMillis']! as num).toInt(),
      nextAttemptAtMillis: (row['nextAttemptAtMillis'] as num?)?.toInt() ?? 0,
      lastAttemptAtMillis: (row['lastAttemptAtMillis'] as num?)?.toInt(),
      serverStatus: row['serverStatus'] as String?,
      serverAckAtMillis: (row['serverAckAtMillis'] as num?)?.toInt(),
      lastErrorCode: row['lastErrorCode'] as String?,
    );
  }

  static Map<String, Object?> _map(Object value) =>
      (value as Map).map((key, value) => MapEntry(key.toString(), value));

  static Map<String, Object?>? _mapOrNull(Object? value) =>
      value == null ? null : _map(value);
}
