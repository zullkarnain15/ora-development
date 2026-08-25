import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/final_activity.dart';
import '../domain/activity_sync.dart';
import '../../tracking/domain/location_engine.dart';
import '../../tracking/domain/tracking_models.dart';

abstract interface class ActivityStore {
  Future<bool> insert(FinalActivity activity);
  Future<List<FinalActivity>> pending(String ownerNik);
  Future<bool> markSynced(String activityId, String ownerNik);
  Future<List<SyncQueueEntry>> dueSync(
    String ownerNik,
    int nowMillis, {
    bool force = false,
  });
  Future<bool> beginSync(String queueId, String ownerNik, int nowMillis);
  Future<void> failSync(
    String queueId,
    String ownerNik, {
    required int nowMillis,
    required int nextAttemptAtMillis,
    required String errorCode,
  });
  Future<bool> acknowledgeSync(
    String queueId,
    String activityId,
    String ownerNik, {
    required String serverStatus,
    required int acknowledgedAtMillis,
  });
  Future<List<ActivityRoutePoint>> acceptedRoute(
    String activityId,
    String ownerNik,
  );
  Future<bool> markSyncNotEligible(
    String queueId,
    String activityId,
    String ownerNik, {
    required String reason,
    required int markedAtMillis,
  });
  Future<bool> removeLocalData(String activityId, String ownerNik);
  Future<bool> deleteNotEligible(String activityId, String ownerNik);
  Future<FinalActivity?> latest(String ownerNik);
  Future<List<FinalActivity>> newestFirst(String ownerNik);
  Future<ActivityTotals> totals(String ownerNik);
  Future<void> createRun(RunSession session, RunEvent event);
  Future<void> updateRun(RunSession session, RunEvent event);
  Future<void> recordPointDecision(
    RunSession session,
    PersistedPointDecision point,
  );
  Future<List<PersistedPointDecision>> pointDecisions(
    String sessionId,
    String ownerNik,
  );
  Future<RunSession?> recoverableRun(String ownerNik);
  Future<FinalActivity> finalizeRun(
    RunSession session, {
    double? finalDistanceMeters,
  });
  Future<void> discardRun(String sessionId, String ownerNik);
}

abstract final class ActivityDatabaseSchema {
  static const databaseName = 'ora.db';
  static const currentVersion = 5;
  static const createActivitiesV1 = '''
CREATE TABLE activities (
  activityId TEXT NOT NULL PRIMARY KEY,
  ownerNik TEXT NOT NULL,
  nicknameSnapshot TEXT,
  divisionGuildSnapshot TEXT,
  startDateTimeMillis INTEGER NOT NULL,
  endDateTimeMillis INTEGER NOT NULL,
  distanceMeters REAL NOT NULL,
  activeDurationMillis INTEGER NOT NULL,
  averagePaceSecondsPerKm INTEGER,
  createdAtMillis INTEGER NOT NULL,
  source TEXT NOT NULL DEFAULT 'ANDROID',
  sourceRef TEXT,
  sourceUrl TEXT,
  syncStatus TEXT NOT NULL
)''';
  static const createOwnerStartIndex =
      'CREATE INDEX IF NOT EXISTS index_activities_owner_start ON activities(ownerNik, startDateTimeMillis)';
  static const createOwnerCreatedIndex =
      'CREATE INDEX IF NOT EXISTS index_activities_owner_created ON activities(ownerNik, createdAtMillis)';
  static const createSchemaMetadataV2 = '''
CREATE TABLE IF NOT EXISTS schema_metadata (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
)''';
  static const createRunSessionsV3 = '''
CREATE TABLE IF NOT EXISTS run_sessions (
  sessionId TEXT NOT NULL PRIMARY KEY,
  ownerNik TEXT NOT NULL,
  nicknameSnapshot TEXT,
  divisionGuildSnapshot TEXT,
  status TEXT NOT NULL,
  policyVersion INTEGER NOT NULL,
  startEpochMillis INTEGER NOT NULL,
  endEpochMillis INTEGER,
  startMonotonicMillis INTEGER NOT NULL,
  bootEpochMillis INTEGER NOT NULL,
  activeAccumulatedMillis INTEGER NOT NULL,
  activeAnchorMonotonicMillis INTEGER,
  lastCheckpointMonotonicMillis INTEGER NOT NULL,
  distanceMeters REAL NOT NULL,
  acceptedPoints INTEGER NOT NULL,
  rejectedPoints INTEGER NOT NULL,
  lastRejectReason TEXT,
  finalActivityId TEXT UNIQUE,
  createdAtMillis INTEGER NOT NULL,
  updatedAtMillis INTEGER NOT NULL
)''';
  static const createLocationPointsV3 = '''
CREATE TABLE IF NOT EXISTS location_points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sessionId TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracyMeters REAL,
  provider TEXT NOT NULL,
  providerMonotonicMillis INTEGER NOT NULL,
  receivedMonotonicMillis INTEGER NOT NULL,
  epochMillis INTEGER NOT NULL,
  isMocked INTEGER NOT NULL,
  decision TEXT NOT NULL,
  rejectReason TEXT,
  segmentMeters REAL NOT NULL,
  UNIQUE(sessionId, sequence)
)''';
  static const createRunEventsV3 = '''
CREATE TABLE IF NOT EXISTS run_events (
  eventId TEXT NOT NULL PRIMARY KEY,
  sessionId TEXT NOT NULL,
  type TEXT NOT NULL,
  fromStatus TEXT,
  toStatus TEXT,
  monotonicMillis INTEGER NOT NULL,
  epochMillis INTEGER NOT NULL,
  details TEXT
)''';
  static const createSyncQueueV4 = '''
CREATE TABLE IF NOT EXISTS sync_queue (
  queueId TEXT NOT NULL PRIMARY KEY,
  activityId TEXT NOT NULL UNIQUE,
  ownerNik TEXT NOT NULL,
  kind TEXT NOT NULL,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  retryCount INTEGER NOT NULL DEFAULT 0,
  payloadVersion INTEGER NOT NULL DEFAULT 1,
  payloadJson TEXT,
  lastAttemptAtMillis INTEGER,
  nextAttemptAtMillis INTEGER NOT NULL DEFAULT 0,
  serverStatus TEXT,
  serverAckAtMillis INTEGER,
  lastErrorCode TEXT,
  createdAtMillis INTEGER NOT NULL,
  updatedAtMillis INTEGER NOT NULL
)''';
  static const createRecoverableRunIndex =
      'CREATE INDEX IF NOT EXISTS index_run_sessions_owner_status ON run_sessions(ownerNik, status, updatedAtMillis)';
  static const createLocationSessionIndex =
      'CREATE INDEX IF NOT EXISTS index_location_points_session_sequence ON location_points(sessionId, sequence)';
  static const createRunEventSessionIndex =
      'CREATE INDEX IF NOT EXISTS index_run_events_session_epoch ON run_events(sessionId, epochMillis)';

  static Future<void> create(Database db, int version) async {
    await db.execute(createActivitiesV1);
    await db.execute(createOwnerStartIndex);
    await db.execute(createOwnerCreatedIndex);
    await db.execute(createSchemaMetadataV2);
    await _createTrackingV3(db);
    await db.insert('schema_metadata', {
      'key': 'schema_owner',
      'value': 'flutter',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(createOwnerStartIndex);
      await db.execute(createOwnerCreatedIndex);
      await db.execute(createSchemaMetadataV2);
      await db.insert('schema_metadata', {
        'key': 'migrated_from',
        'value': 'android_v1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (oldVersion < 3) {
      await _createTrackingV3(db);
    }
    if (oldVersion >= 3 && oldVersion < 4) {
      await _upgradeSyncV4(db);
    }
    if (oldVersion < 5) {
      await _upgradeActivitySourceV5(db);
    }
  }

  static Future<void> _createTrackingV3(DatabaseExecutor db) async {
    await db.execute(createRunSessionsV3);
    await db.execute(createLocationPointsV3);
    await db.execute(createRunEventsV3);
    await db.execute(createSyncQueueV4);
    await db.execute(createRecoverableRunIndex);
    await db.execute(createLocationSessionIndex);
    await db.execute(createRunEventSessionIndex);
  }

  static Future<void> _upgradeSyncV4(DatabaseExecutor db) async {
    for (final statement in const [
      'ALTER TABLE sync_queue ADD COLUMN retryCount INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE sync_queue ADD COLUMN payloadVersion INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE sync_queue ADD COLUMN payloadJson TEXT',
      'ALTER TABLE sync_queue ADD COLUMN lastAttemptAtMillis INTEGER',
      'ALTER TABLE sync_queue ADD COLUMN nextAttemptAtMillis INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE sync_queue ADD COLUMN serverStatus TEXT',
      'ALTER TABLE sync_queue ADD COLUMN serverAckAtMillis INTEGER',
      'ALTER TABLE sync_queue ADD COLUMN lastErrorCode TEXT',
    ]) {
      await db.execute(statement);
    }
  }

  static Future<void> _upgradeActivitySourceV5(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(activities)'))
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    for (final entry in const {
      'source': "ALTER TABLE activities ADD COLUMN source TEXT NOT NULL DEFAULT 'ANDROID'",
      'sourceRef': 'ALTER TABLE activities ADD COLUMN sourceRef TEXT',
      'sourceUrl': 'ALTER TABLE activities ADD COLUMN sourceUrl TEXT',
    }.entries) {
      if (!columns.contains(entry.key)) await db.execute(entry.value);
    }
  }
}

class SqfliteActivityStore implements ActivityStore {
  SqfliteActivityStore({DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory;
  final DatabaseFactory _factory;
  Database? _database;

  Future<Database> get _db async => _database ??= await _factory.openDatabase(
    path.join(
      await _factory.getDatabasesPath(),
      ActivityDatabaseSchema.databaseName,
    ),
    options: OpenDatabaseOptions(
      version: ActivityDatabaseSchema.currentVersion,
      onCreate: ActivityDatabaseSchema.create,
      onUpgrade: ActivityDatabaseSchema.upgrade,
    ),
  );

  @override
  Future<bool> insert(FinalActivity activity) async {
    final reason = activitySyncIneligibilityReason(activity);
    final storedActivity = reason == null
        ? activity
        : activity.withSyncStatus(ActivitySyncStatus.notEligible);
    return (await _db).transaction((txn) async {
      final result = await txn.insert(
        'activities',
        storedActivity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (result == 0) return false;
      if (reason == null &&
          (storedActivity.syncStatus == ActivitySyncStatus.pending ||
              storedActivity.syncStatus == ActivitySyncStatus.localOnly)) {
        await _enqueueActivity(txn, storedActivity);
      }
      return true;
    });
  }

  @override
  Future<List<FinalActivity>> pending(String ownerNik) => _query(
    ownerNik,
    whereSuffix: 'AND syncStatus IN (?, ?)',
    extraArgs: [
      ActivitySyncStatus.pending.value,
      ActivitySyncStatus.localOnly.value,
    ],
  );

  @override
  Future<bool> markSynced(String activityId, String ownerNik) async {
    final rows = await (await _db).query(
      'sync_queue',
      columns: ['queueId'],
      where: 'activityId = ? AND ownerNik = ?',
      whereArgs: [activityId, ownerNik],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return acknowledgeSync(
      rows.first['queueId']! as String,
      activityId,
      ownerNik,
      serverStatus: 'LEGACY_ACK',
      acknowledgedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<List<SyncQueueEntry>> dueSync(
    String ownerNik,
    int nowMillis, {
    bool force = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sync_queue',
      where:
          'ownerNik = ? AND state NOT IN (?, ?) ${force ? '' : 'AND nextAttemptAtMillis <= ?'}',
      whereArgs: [
        ownerNik,
        SyncQueueState.acknowledged.value,
        SyncQueueState.notEligible.value,
        if (!force) nowMillis,
      ],
      orderBy: 'createdAtMillis ASC',
    );
    final result = <SyncQueueEntry>[];
    for (final row in rows) {
      var payloadJson = row['payloadJson'] as String?;
      var payloadVersion = (row['payloadVersion'] as num?)?.toInt() ?? 1;
      if (payloadJson == null || payloadJson.isEmpty) {
        final activityRows = await db.query(
          'activities',
          where: 'activityId = ? AND ownerNik = ?',
          whereArgs: [row['activityId'], ownerNik],
          limit: 1,
        );
        if (activityRows.isEmpty) continue;
        final activity = FinalActivity.fromMap(activityRows.first);
        final payload = ActivityPayloadMapper.mapV2(
          activity,
          deviceTime: DateTime.fromMillisecondsSinceEpoch(
            activity.createdAtMillis,
          ),
        );
        payloadJson = payload.encode();
        payloadVersion = payload.version;
        await db.update(
          'sync_queue',
          {'payloadJson': payloadJson, 'payloadVersion': payloadVersion},
          where: 'queueId = ? AND ownerNik = ?',
          whereArgs: [row['queueId'], ownerNik],
        );
      }
      result.add(_syncEntry(row, payloadVersion, payloadJson));
    }
    return result;
  }

  @override
  Future<bool> beginSync(String queueId, String ownerNik, int nowMillis) async {
    final count = await (await _db).rawUpdate(
      '''UPDATE sync_queue
SET state = ?, retryCount = retryCount + 1, attempts = attempts + 1,
    lastAttemptAtMillis = ?, updatedAtMillis = ?, lastErrorCode = NULL
WHERE queueId = ? AND ownerNik = ? AND state NOT IN (?, ?)''',
      [
        SyncQueueState.uploading.value,
        nowMillis,
        nowMillis,
        queueId,
        ownerNik,
        SyncQueueState.acknowledged.value,
        SyncQueueState.notEligible.value,
      ],
    );
    return count == 1;
  }

  @override
  Future<void> failSync(
    String queueId,
    String ownerNik, {
    required int nowMillis,
    required int nextAttemptAtMillis,
    required String errorCode,
  }) async {
    await (await _db).update(
      'sync_queue',
      {
        'state': SyncQueueState.retry.value,
        'nextAttemptAtMillis': nextAttemptAtMillis,
        'lastErrorCode': errorCode,
        'updatedAtMillis': nowMillis,
      },
      where: 'queueId = ? AND ownerNik = ? AND state = ?',
      whereArgs: [queueId, ownerNik, SyncQueueState.uploading.value],
    );
  }

  @override
  Future<bool> acknowledgeSync(
    String queueId,
    String activityId,
    String ownerNik, {
    required String serverStatus,
    required int acknowledgedAtMillis,
  }) async {
    return (await _db).transaction((txn) async {
      final acked = await txn.update(
        'sync_queue',
        {
          'state': SyncQueueState.acknowledged.value,
          'serverStatus': serverStatus,
          'serverAckAtMillis': acknowledgedAtMillis,
          'updatedAtMillis': acknowledgedAtMillis,
          'lastErrorCode': null,
        },
        where: 'queueId = ? AND activityId = ? AND ownerNik = ?',
        whereArgs: [queueId, activityId, ownerNik],
      );
      if (acked != 1) return false;
      final activityUpdated = await txn.update(
        'activities',
        {'syncStatus': ActivitySyncStatus.synced.value},
        where: 'activityId = ? AND ownerNik = ?',
        whereArgs: [activityId, ownerNik],
      );
      if (activityUpdated != 1) {
        throw StateError('ACK activity owner mismatch.');
      }
      return true;
    });
  }

  @override
  Future<bool> markSyncNotEligible(
    String queueId,
    String activityId,
    String ownerNik, {
    required String reason,
    required int markedAtMillis,
  }) async {
    return (await _db).transaction((txn) async {
      final queueUpdated = await txn.update(
        'sync_queue',
        {
          'state': SyncQueueState.notEligible.value,
          'lastErrorCode': reason,
          'updatedAtMillis': markedAtMillis,
        },
        where: 'queueId = ? AND activityId = ? AND ownerNik = ?',
        whereArgs: [queueId, activityId, ownerNik],
      );
      if (queueUpdated != 1) return false;
      final activityUpdated = await txn.update(
        'activities',
        {'syncStatus': ActivitySyncStatus.notEligible.value},
        where: 'activityId = ? AND ownerNik = ?',
        whereArgs: [activityId, ownerNik],
      );
      if (activityUpdated != 1) {
        throw StateError('Ineligible activity owner mismatch.');
      }
      return true;
    });
  }

  @override
  Future<bool> deleteNotEligible(String activityId, String ownerNik) async {
    return _removeLocalData(
      activityId,
      ownerNik,
      allowedStatuses: const {ActivitySyncStatus.notEligible},
    );
  }

  @override
  Future<bool> removeLocalData(String activityId, String ownerNik) async {
    return _removeLocalData(activityId, ownerNik);
  }

  Future<bool> _removeLocalData(
    String activityId,
    String ownerNik, {
    Set<ActivitySyncStatus>? allowedStatuses,
  }) async {
    return (await _db).transaction((txn) async {
      final activities = await txn.query(
        'activities',
        columns: ['syncStatus'],
        where: 'activityId = ? AND ownerNik = ?',
        whereArgs: [activityId, ownerNik],
        limit: 1,
      );
      if (activities.isEmpty) return false;
      final syncStatus = ActivitySyncStatusValue.parse(
        activities.single['syncStatus']! as String,
      );
      if (allowedStatuses != null && !allowedStatuses.contains(syncStatus)) {
        return false;
      }
      final runs = await txn.query(
        'run_sessions',
        columns: ['sessionId'],
        where: 'finalActivityId = ? AND ownerNik = ?',
        whereArgs: [activityId, ownerNik],
      );
      for (final run in runs) {
        final sessionId = run['sessionId']! as String;
        await txn.delete(
          'location_points',
          where: 'sessionId = ?',
          whereArgs: [sessionId],
        );
        await txn.delete(
          'run_events',
          where: 'sessionId = ?',
          whereArgs: [sessionId],
        );
        await txn.delete(
          'run_sessions',
          where: 'sessionId = ? AND ownerNik = ?',
          whereArgs: [sessionId, ownerNik],
        );
      }
      await txn.delete(
        'sync_queue',
        where: 'activityId = ? AND ownerNik = ?',
        whereArgs: [activityId, ownerNik],
      );
      return await txn.delete(
            'activities',
            where: 'activityId = ? AND ownerNik = ?',
            whereArgs: [activityId, ownerNik],
          ) ==
          1;
    });
  }

  @override
  Future<List<ActivityRoutePoint>> acceptedRoute(
    String activityId,
    String ownerNik,
  ) async {
    final rows = await (await _db).rawQuery(
      '''SELECT p.latitude, p.longitude, p.sequence
FROM location_points p
JOIN run_sessions r ON r.sessionId = p.sessionId
WHERE r.finalActivityId = ? AND r.ownerNik = ?
  AND p.decision IN (?, ?, ?)
ORDER BY p.sequence ASC''',
      [
        activityId,
        ownerNik,
        LocationDecisionType.baseline.value,
        LocationDecisionType.reentryBaseline.value,
        LocationDecisionType.accepted.value,
      ],
    );
    return rows
        .map(
          (row) => ActivityRoutePoint(
            latitude: (row['latitude']! as num).toDouble(),
            longitude: (row['longitude']! as num).toDouble(),
            sequence: (row['sequence']! as num).toInt(),
          ),
        )
        .toList(growable: false);
  }

  SyncQueueEntry _syncEntry(
    Map<String, Object?> row,
    int payloadVersion,
    String payloadJson,
  ) => SyncQueueEntry(
    queueId: row['queueId']! as String,
    activityId: row['activityId']! as String,
    ownerNik: row['ownerNik']! as String,
    state: SyncQueueStateValue.parse(row['state'] as String?),
    retryCount: (row['retryCount'] as num?)?.toInt() ?? 0,
    payload: ActivityUploadPayload.decode(payloadVersion, payloadJson),
    createdAtMillis: (row['createdAtMillis']! as num).toInt(),
    updatedAtMillis: (row['updatedAtMillis']! as num).toInt(),
    nextAttemptAtMillis: (row['nextAttemptAtMillis'] as num?)?.toInt() ?? 0,
    lastAttemptAtMillis: (row['lastAttemptAtMillis'] as num?)?.toInt(),
    serverStatus: row['serverStatus'] as String?,
    serverAckAtMillis: (row['serverAckAtMillis'] as num?)?.toInt(),
    lastErrorCode: row['lastErrorCode'] as String?,
  );

  Future<void> _enqueueActivity(
    DatabaseExecutor db,
    FinalActivity activity,
  ) async {
    final payload = ActivityPayloadMapper.mapV2(
      activity,
      deviceTime: DateTime.fromMillisecondsSinceEpoch(activity.createdAtMillis),
    );
    await db.insert('sync_queue', {
      'queueId': 'activity_${activity.activityId}',
      'activityId': activity.activityId,
      'ownerNik': activity.ownerNik,
      'kind': 'ACTIVITY_UPLOAD',
      'state': SyncQueueState.pending.value,
      'attempts': 0,
      'retryCount': 0,
      'payloadVersion': payload.version,
      'payloadJson': payload.encode(),
      'nextAttemptAtMillis': 0,
      'createdAtMillis': activity.createdAtMillis,
      'updatedAtMillis': activity.createdAtMillis,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<FinalActivity?> latest(String ownerNik) async {
    final rows = await (await _db).query(
      'activities',
      where: 'ownerNik = ?',
      whereArgs: [ownerNik],
      orderBy: 'startDateTimeMillis DESC, createdAtMillis DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : FinalActivity.fromMap(rows.first);
  }

  @override
  Future<List<FinalActivity>> newestFirst(String ownerNik) => _query(ownerNik);

  Future<List<FinalActivity>> _query(
    String ownerNik, {
    String whereSuffix = '',
    List<Object?> extraArgs = const [],
  }) async {
    final rows = await (await _db).query(
      'activities',
      where: 'ownerNik = ? $whereSuffix',
      whereArgs: [ownerNik, ...extraArgs],
      orderBy: 'startDateTimeMillis DESC, createdAtMillis DESC',
    );
    return rows.map(FinalActivity.fromMap).toList(growable: false);
  }

  @override
  Future<ActivityTotals> totals(String ownerNik) async {
    final rows = await (await _db).rawQuery(
      '''
SELECT COUNT(*) AS activityCount,
       COALESCE(SUM(distanceMeters), 0.0) AS totalDistanceMeters,
       COALESCE(SUM(activeDurationMillis), 0) AS totalActiveDurationMillis
FROM activities WHERE ownerNik = ?
''',
      [ownerNik],
    );
    final row = rows.first;
    return ActivityTotals(
      activityCount: (row['activityCount']! as num).toInt(),
      totalDistanceMeters: (row['totalDistanceMeters']! as num).toDouble(),
      totalActiveDurationMillis: (row['totalActiveDurationMillis']! as num)
          .toInt(),
    );
  }

  @override
  Future<void> createRun(RunSession session, RunEvent event) async {
    await (await _db).transaction((txn) async {
      await txn.insert(
        'run_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert('run_events', event.toMap());
    });
  }

  @override
  Future<void> updateRun(RunSession session, RunEvent event) async {
    await (await _db).transaction((txn) async {
      final count = await txn.update(
        'run_sessions',
        session.toMap(),
        where: 'sessionId = ? AND ownerNik = ?',
        whereArgs: [session.sessionId, session.ownerNik],
      );
      if (count != 1) throw StateError('Run session was not found.');
      await txn.insert(
        'run_events',
        event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  @override
  Future<void> recordPointDecision(
    RunSession session,
    PersistedPointDecision point,
  ) async {
    await (await _db).transaction((txn) async {
      await txn.insert(
        'location_points',
        point.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final count = await txn.update(
        'run_sessions',
        session.toMap(),
        where: 'sessionId = ? AND ownerNik = ?',
        whereArgs: [session.sessionId, session.ownerNik],
      );
      if (count != 1) throw StateError('Run session was not found.');
    });
  }

  @override
  Future<RunSession?> recoverableRun(String ownerNik) async {
    final rows = await (await _db).query(
      'run_sessions',
      where: 'ownerNik = ? AND status NOT IN (?, ?, ?)',
      whereArgs: [
        ownerNik,
        TrackingStatus.idle.value,
        TrackingStatus.finished.value,
        TrackingStatus.error.value,
      ],
      orderBy: 'updatedAtMillis DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : RunSession.fromMap(rows.first);
  }

  @override
  Future<List<PersistedPointDecision>> pointDecisions(
    String sessionId,
    String ownerNik,
  ) async {
    final rows = await (await _db).rawQuery(
      '''SELECT p.sessionId, p.sequence, p.latitude, p.longitude,
       p.accuracyMeters, p.provider, p.providerMonotonicMillis,
       p.receivedMonotonicMillis, p.epochMillis, p.isMocked,
       p.decision, p.rejectReason, p.segmentMeters
FROM location_points p
JOIN run_sessions r ON r.sessionId = p.sessionId
WHERE p.sessionId = ? AND r.ownerNik = ?
ORDER BY p.sequence ASC''',
      [sessionId, ownerNik],
    );
    return rows.map(PersistedPointDecision.fromMap).toList(growable: false);
  }

  @override
  Future<FinalActivity> finalizeRun(
    RunSession session, {
    double? finalDistanceMeters,
  }) async {
    return (await _db).transaction((txn) async {
      final currentRows = await txn.query(
        'run_sessions',
        where: 'sessionId = ? AND ownerNik = ?',
        whereArgs: [session.sessionId, session.ownerNik],
        limit: 1,
      );
      if (currentRows.isEmpty) throw StateError('Run session was not found.');
      final current = RunSession.fromMap(currentRows.first);
      if (current.finalActivityId != null) {
        final rows = await txn.query(
          'activities',
          where: 'activityId = ? AND ownerNik = ?',
          whereArgs: [current.finalActivityId, current.ownerNik],
          limit: 1,
        );
        if (rows.isNotEmpty) return FinalActivity.fromMap(rows.first);
      }
      final distanceRows = await txn.rawQuery(
        '''SELECT COALESCE(SUM(segmentMeters), 0.0) AS distance
FROM location_points WHERE sessionId = ? AND decision = ?''',
        [session.sessionId, LocationDecisionType.accepted.value],
      );
      final integratedDistance = (distanceRows.first['distance']! as num)
          .toDouble();
      final reconciledDistance =
          finalDistanceMeters != null &&
              finalDistanceMeters.isFinite &&
              finalDistanceMeters >= 0 &&
              finalDistanceMeters <= integratedDistance
          ? finalDistanceMeters
          : integratedDistance;
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
        syncStatus:
            reconciledDistance > 0 && session.activeAccumulatedMillis > 0
            ? ActivitySyncStatus.pending
            : ActivitySyncStatus.notEligible,
      );
      await txn.insert(
        'activities',
        activity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (activity.syncStatus == ActivitySyncStatus.pending) {
        await _enqueueActivity(txn, activity);
      }
      await txn.update(
        'run_sessions',
        session
            .copyWith(
              status: TrackingStatus.finished,
              distanceMeters: reconciledDistance,
              finalActivityId: activityId,
            )
            .toMap(),
        where: 'sessionId = ? AND ownerNik = ?',
        whereArgs: [session.sessionId, session.ownerNik],
      );
      return activity;
    });
  }

  @override
  Future<void> discardRun(String sessionId, String ownerNik) async {
    await (await _db).transaction((txn) async {
      final rows = await txn.query(
        'run_sessions',
        columns: ['finalActivityId'],
        where: 'sessionId = ? AND ownerNik = ?',
        whereArgs: [sessionId, ownerNik],
      );
      if (rows.isEmpty || rows.first['finalActivityId'] != null) return;
      await txn.delete(
        'location_points',
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'run_events',
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'run_sessions',
        where: 'sessionId = ? AND ownerNik = ?',
        whereArgs: [sessionId, ownerNik],
      );
    });
  }
}

class MemoryActivityStore implements ActivityStore {
  final Map<String, FinalActivity> _items = {};
  final Map<String, RunSession> _runs = {};
  final Map<String, List<PersistedPointDecision>> _points = {};
  final Map<String, RunEvent> _events = {};
  final Map<String, SyncQueueEntry> _syncQueue = {};

  @override
  Future<bool> insert(FinalActivity activity) async {
    if (_items.containsKey(activity.activityId)) return false;
    final reason = activitySyncIneligibilityReason(activity);
    final storedActivity = reason == null
        ? activity
        : activity.withSyncStatus(ActivitySyncStatus.notEligible);
    _items[activity.activityId] = storedActivity;
    if (reason == null &&
        (storedActivity.syncStatus == ActivitySyncStatus.pending ||
            storedActivity.syncStatus == ActivitySyncStatus.localOnly)) {
      _enqueueMemory(storedActivity);
    }
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
  Future<bool> markSynced(String activityId, String ownerNik) async {
    final queueId = 'activity_$activityId';
    return acknowledgeSync(
      queueId,
      activityId,
      ownerNik,
      serverStatus: 'LEGACY_ACK',
      acknowledgedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<List<SyncQueueEntry>> dueSync(
    String ownerNik,
    int nowMillis, {
    bool force = false,
  }) async {
    final values =
        _syncQueue.values
            .where(
              (item) =>
                  item.ownerNik == ownerNik &&
                  item.state != SyncQueueState.acknowledged &&
                  item.state != SyncQueueState.notEligible &&
                  (force || item.nextAttemptAtMillis <= nowMillis),
            )
            .toList()
          ..sort((a, b) => a.createdAtMillis.compareTo(b.createdAtMillis));
    return List.unmodifiable(values);
  }

  @override
  Future<bool> beginSync(String queueId, String ownerNik, int nowMillis) async {
    final item = _syncQueue[queueId];
    if (item == null ||
        item.ownerNik != ownerNik ||
        item.state == SyncQueueState.acknowledged ||
        item.state == SyncQueueState.notEligible) {
      return false;
    }
    _syncQueue[queueId] = _copySync(
      item,
      state: SyncQueueState.uploading,
      retryCount: item.retryCount + 1,
      lastAttemptAtMillis: nowMillis,
      updatedAtMillis: nowMillis,
      clearError: true,
    );
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
    final item = _syncQueue[queueId];
    if (item == null || item.ownerNik != ownerNik) return;
    _syncQueue[queueId] = _copySync(
      item,
      state: SyncQueueState.retry,
      nextAttemptAtMillis: nextAttemptAtMillis,
      updatedAtMillis: nowMillis,
      lastErrorCode: errorCode,
    );
  }

  @override
  Future<bool> acknowledgeSync(
    String queueId,
    String activityId,
    String ownerNik, {
    required String serverStatus,
    required int acknowledgedAtMillis,
  }) async {
    final queue = _syncQueue[queueId];
    final activity = _items[activityId];
    if (queue == null ||
        activity == null ||
        queue.activityId != activityId ||
        queue.ownerNik != ownerNik ||
        activity.ownerNik != ownerNik) {
      return false;
    }
    _syncQueue[queueId] = _copySync(
      queue,
      state: SyncQueueState.acknowledged,
      serverStatus: serverStatus,
      serverAckAtMillis: acknowledgedAtMillis,
      updatedAtMillis: acknowledgedAtMillis,
      clearError: true,
    );
    _items[activityId] = FinalActivity(
      activityId: activity.activityId,
      ownerNik: activity.ownerNik,
      nicknameSnapshot: activity.nicknameSnapshot,
      divisionGuildSnapshot: activity.divisionGuildSnapshot,
      startDateTimeMillis: activity.startDateTimeMillis,
      endDateTimeMillis: activity.endDateTimeMillis,
      distanceMeters: activity.distanceMeters,
      activeDurationMillis: activity.activeDurationMillis,
      averagePaceSecondsPerKm: activity.averagePaceSecondsPerKm,
      createdAtMillis: activity.createdAtMillis,
      source: activity.source,
      sourceRef: activity.sourceRef,
      sourceUrl: activity.sourceUrl,
      syncStatus: ActivitySyncStatus.synced,
    );
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
    final queue = _syncQueue[queueId];
    final activity = _items[activityId];
    if (queue == null ||
        activity == null ||
        queue.activityId != activityId ||
        queue.ownerNik != ownerNik ||
        activity.ownerNik != ownerNik) {
      return false;
    }
    _syncQueue[queueId] = _copySync(
      queue,
      state: SyncQueueState.notEligible,
      updatedAtMillis: markedAtMillis,
      lastErrorCode: reason,
    );
    _items[activityId] = activity.withSyncStatus(
      ActivitySyncStatus.notEligible,
    );
    return true;
  }

  @override
  Future<bool> deleteNotEligible(String activityId, String ownerNik) async {
    return _removeLocalData(
      activityId,
      ownerNik,
      allowedStatuses: const {ActivitySyncStatus.notEligible},
    );
  }

  @override
  Future<bool> removeLocalData(String activityId, String ownerNik) async {
    return _removeLocalData(activityId, ownerNik);
  }

  Future<bool> _removeLocalData(
    String activityId,
    String ownerNik, {
    Set<ActivitySyncStatus>? allowedStatuses,
  }) async {
    final activity = _items[activityId];
    if (activity == null || activity.ownerNik != ownerNik) {
      return false;
    }
    if (allowedStatuses != null &&
        !allowedStatuses.contains(activity.syncStatus)) {
      return false;
    }
    final runIds = _runs.values
        .where(
          (run) =>
              run.ownerNik == ownerNik && run.finalActivityId == activityId,
        )
        .map((run) => run.sessionId)
        .toList(growable: false);
    for (final sessionId in runIds) {
      _points.remove(sessionId);
      _events.removeWhere((_, event) => event.sessionId == sessionId);
      _runs.remove(sessionId);
    }
    _syncQueue.remove('activity_$activityId');
    _items.remove(activityId);
    return true;
  }

  @override
  Future<List<ActivityRoutePoint>> acceptedRoute(
    String activityId,
    String ownerNik,
  ) async {
    final run = _runs.values.where(
      (item) => item.ownerNik == ownerNik && item.finalActivityId == activityId,
    );
    if (run.isEmpty) return const [];
    final values =
        (_points[run.first.sessionId] ?? const [])
            .where(
              (item) =>
                  item.decision.type == LocationDecisionType.baseline ||
                  item.decision.type == LocationDecisionType.reentryBaseline ||
                  item.decision.type == LocationDecisionType.accepted,
            )
            .map(
              (item) => ActivityRoutePoint(
                latitude: item.sample.latitude,
                longitude: item.sample.longitude,
                sequence: item.sample.sequence,
              ),
            )
            .toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return List.unmodifiable(values);
  }

  @override
  Future<FinalActivity?> latest(String ownerNik) async {
    final items = await newestFirst(ownerNik);
    return items.isEmpty ? null : items.first;
  }

  @override
  Future<List<FinalActivity>> newestFirst(String ownerNik) async {
    final items = _items.values
        .where((item) => item.ownerNik == ownerNik)
        .toList();
    items.sort((a, b) {
      final byStart = b.startDateTimeMillis.compareTo(a.startDateTimeMillis);
      return byStart != 0
          ? byStart
          : b.createdAtMillis.compareTo(a.createdAtMillis);
    });
    return items;
  }

  @override
  Future<ActivityTotals> totals(String ownerNik) async {
    final items = await newestFirst(ownerNik);
    return ActivityTotals(
      activityCount: items.length,
      totalDistanceMeters: items.fold(
        0,
        (sum, item) => sum + item.distanceMeters,
      ),
      totalActiveDurationMillis: items.fold(
        0,
        (sum, item) => sum + item.activeDurationMillis,
      ),
    );
  }

  @override
  Future<void> createRun(RunSession session, RunEvent event) async {
    if (_runs.containsKey(session.sessionId)) {
      throw StateError('Duplicate run session.');
    }
    _runs[session.sessionId] = session;
    _events[event.eventId] = event;
  }

  @override
  Future<void> updateRun(RunSession session, RunEvent event) async {
    if (!_runs.containsKey(session.sessionId)) {
      throw StateError('Run session was not found.');
    }
    _runs[session.sessionId] = session;
    _events[event.eventId] = event;
  }

  @override
  Future<void> recordPointDecision(
    RunSession session,
    PersistedPointDecision point,
  ) async {
    if (!_runs.containsKey(session.sessionId)) {
      throw StateError('Run session was not found.');
    }
    final points = _points.putIfAbsent(session.sessionId, () => []);
    if (!points.any((item) => item.sample.sequence == point.sample.sequence)) {
      points.add(point);
    }
    _runs[session.sessionId] = session;
  }

  @override
  Future<RunSession?> recoverableRun(String ownerNik) async {
    final candidates =
        _runs.values
            .where(
              (run) =>
                  run.ownerNik == ownerNik &&
                  run.status != TrackingStatus.idle &&
                  run.status != TrackingStatus.finished &&
                  run.status != TrackingStatus.error,
            )
            .toList()
          ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<List<PersistedPointDecision>> pointDecisions(
    String sessionId,
    String ownerNik,
  ) async {
    final run = _runs[sessionId];
    if (run == null || run.ownerNik != ownerNik) return const [];
    final points = List<PersistedPointDecision>.from(
      _points[sessionId] ?? const <PersistedPointDecision>[],
    )..sort((a, b) => a.sample.sequence.compareTo(b.sample.sequence));
    return List.unmodifiable(points);
  }

  @override
  Future<FinalActivity> finalizeRun(
    RunSession session, {
    double? finalDistanceMeters,
  }) async {
    final current = _runs[session.sessionId];
    if (current == null) throw StateError('Run session was not found.');
    if (current.finalActivityId != null) {
      return _items[current.finalActivityId]!;
    }
    final integratedDistance =
        (_points[session.sessionId] ?? const <PersistedPointDecision>[])
            .where(
              (item) => item.decision.type == LocationDecisionType.accepted,
            )
            .fold<double>(0, (sum, item) => sum + item.decision.segmentMeters);
    final distance =
        finalDistanceMeters != null &&
            finalDistanceMeters.isFinite &&
            finalDistanceMeters >= 0 &&
            finalDistanceMeters <= integratedDistance
        ? finalDistanceMeters
        : integratedDistance;
    final activityId = 'run_${session.sessionId}';
    final end = session.endEpochMillis ?? session.updatedAtMillis;
    final activity = FinalActivity(
      activityId: activityId,
      ownerNik: session.ownerNik,
      nicknameSnapshot: session.nicknameSnapshot,
      divisionGuildSnapshot: session.divisionGuildSnapshot,
      startDateTimeMillis: session.startEpochMillis,
      endDateTimeMillis: end,
      distanceMeters: distance,
      activeDurationMillis: session.activeAccumulatedMillis,
      averagePaceSecondsPerKm: averagePaceSecondsPerKm(
        session.activeAccumulatedMillis,
        distance,
      ),
      createdAtMillis: end,
      syncStatus: distance > 0 && session.activeAccumulatedMillis > 0
          ? ActivitySyncStatus.pending
          : ActivitySyncStatus.notEligible,
    );
    _items[activityId] = activity;
    if (activity.syncStatus == ActivitySyncStatus.pending) {
      _enqueueMemory(activity);
    }
    _runs[session.sessionId] = session.copyWith(
      status: TrackingStatus.finished,
      distanceMeters: distance,
      finalActivityId: activityId,
    );
    return activity;
  }

  @override
  Future<void> discardRun(String sessionId, String ownerNik) async {
    final run = _runs[sessionId];
    if (run == null ||
        run.ownerNik != ownerNik ||
        run.finalActivityId != null) {
      return;
    }
    _runs.remove(sessionId);
    _points.remove(sessionId);
    _events.removeWhere((_, event) => event.sessionId == sessionId);
  }

  void _enqueueMemory(FinalActivity activity) {
    final payload = ActivityPayloadMapper.mapV2(
      activity,
      deviceTime: DateTime.fromMillisecondsSinceEpoch(activity.createdAtMillis),
    );
    final queueId = 'activity_${activity.activityId}';
    _syncQueue.putIfAbsent(
      queueId,
      () => SyncQueueEntry(
        queueId: queueId,
        activityId: activity.activityId,
        ownerNik: activity.ownerNik,
        state: SyncQueueState.pending,
        retryCount: 0,
        payload: payload,
        createdAtMillis: activity.createdAtMillis,
        updatedAtMillis: activity.createdAtMillis,
        nextAttemptAtMillis: 0,
      ),
    );
  }

  SyncQueueEntry _copySync(
    SyncQueueEntry value, {
    SyncQueueState? state,
    int? retryCount,
    int? lastAttemptAtMillis,
    int? nextAttemptAtMillis,
    int? updatedAtMillis,
    String? serverStatus,
    int? serverAckAtMillis,
    String? lastErrorCode,
    bool clearError = false,
  }) => SyncQueueEntry(
    queueId: value.queueId,
    activityId: value.activityId,
    ownerNik: value.ownerNik,
    state: state ?? value.state,
    retryCount: retryCount ?? value.retryCount,
    payload: value.payload,
    createdAtMillis: value.createdAtMillis,
    updatedAtMillis: updatedAtMillis ?? value.updatedAtMillis,
    nextAttemptAtMillis: nextAttemptAtMillis ?? value.nextAttemptAtMillis,
    lastAttemptAtMillis: lastAttemptAtMillis ?? value.lastAttemptAtMillis,
    serverStatus: serverStatus ?? value.serverStatus,
    serverAckAtMillis: serverAckAtMillis ?? value.serverAckAtMillis,
    lastErrorCode: clearError ? null : (lastErrorCode ?? value.lastErrorCode),
  );
}
