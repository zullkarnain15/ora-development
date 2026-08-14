import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

FinalActivity _activity({
  required String id,
  required String owner,
  required int start,
  double distance = 1000,
  int duration = 60000,
  ActivitySyncStatus status = ActivitySyncStatus.pending,
}) => FinalActivity(
  activityId: id,
  ownerNik: owner,
  nicknameSnapshot: 'RUNNER',
  divisionGuildSnapshot: 'OPS',
  startDateTimeMillis: start,
  endDateTimeMillis: start + duration,
  distanceMeters: distance,
  activeDurationMillis: duration,
  averagePaceSecondsPerKm: 300,
  createdAtMillis: start + duration,
  syncStatus: status,
);

void main() {
  group('owner-scoped activity repository', () {
    test('isolates owners, sorts newest first, and aggregates', () async {
      final store = MemoryActivityStore();
      await store.insert(
        _activity(
          id: 'A1',
          owner: '1001',
          start: 100,
          distance: 1000,
          duration: 10000,
        ),
      );
      await store.insert(
        _activity(
          id: 'A2',
          owner: '1001',
          start: 300,
          distance: 2500,
          duration: 20000,
        ),
      );
      await store.insert(
        _activity(
          id: 'B1',
          owner: '2002',
          start: 500,
          distance: 9000,
          duration: 90000,
        ),
      );

      expect((await store.newestFirst('1001')).map((item) => item.activityId), [
        'A2',
        'A1',
      ]);
      expect((await store.latest('1001'))?.activityId, 'A2');
      final totals = await store.totals('1001');
      expect(totals.activityCount, 2);
      expect(totals.totalDistanceMeters, 3500);
      expect(totals.totalActiveDurationMillis, 30000);
      expect(
        (await store.newestFirst('1001'))
            .any((item) => item.ownerNik == '2002'),
        isFalse,
      );
    });

    test('primary key duplicates are ignored', () async {
      final store = MemoryActivityStore();
      expect(
        await store.insert(_activity(id: 'A1', owner: '1001', start: 1)),
        isTrue,
      );
      expect(
        await store.insert(_activity(id: 'A1', owner: '1001', start: 2)),
        isFalse,
      );
      expect((await store.newestFirst('1001')), hasLength(1));
    });

    test('pending and synced transitions require matching owner', () async {
      final store = MemoryActivityStore();
      await store.insert(_activity(id: 'A1', owner: '1001', start: 1));
      expect(await store.markSynced('A1', '2002'), isFalse);
      expect(await store.pending('1001'), hasLength(1));
      expect(await store.markSynced('A1', '1001'), isTrue);
      expect(await store.pending('1001'), isEmpty);
      expect(
        (await store.newestFirst('1001')).single.syncStatus,
        ActivitySyncStatus.synced,
      );
    });

    test(
      'zero-distance activity is terminal local-only and deletable',
      () async {
        final store = MemoryActivityStore();
        await store.insert(
          _activity(
            id: 'ZERO',
            owner: '1001',
            start: 1,
            distance: 0,
            duration: 10000,
          ),
        );
        final stored = (await store.newestFirst('1001')).single;
        expect(stored.syncStatus, ActivitySyncStatus.notEligible);
        expect(await store.pending('1001'), isEmpty);
        expect(await store.dueSync('1001', 100000, force: true), isEmpty);
        expect(await store.deleteNotEligible('ZERO', '2002'), isFalse);
        expect(await store.deleteNotEligible('ZERO', '1001'), isTrue);
        expect(await store.newestFirst('1001'), isEmpty);
      },
    );

    test('missing pace alone remains eligible for sync', () async {
      final store = MemoryActivityStore();
      final activity = _activity(id: 'NO-PACE', owner: '1001', start: 1);
      await store.insert(
        FinalActivity(
          activityId: activity.activityId,
          ownerNik: activity.ownerNik,
          nicknameSnapshot: activity.nicknameSnapshot,
          divisionGuildSnapshot: activity.divisionGuildSnapshot,
          startDateTimeMillis: activity.startDateTimeMillis,
          endDateTimeMillis: activity.endDateTimeMillis,
          distanceMeters: activity.distanceMeters,
          activeDurationMillis: activity.activeDurationMillis,
          averagePaceSecondsPerKm: null,
          createdAtMillis: activity.createdAtMillis,
        ),
      );
      expect(await store.pending('1001'), hasLength(1));
      expect(await store.dueSync('1001', 100000, force: true), hasLength(1));
    });
  });

  test('Android ora.db version 1 fixture upgrades to sync schema version 4 without data loss', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp(
      'ora_db_migration_',
    );
    final databasePath = path.join(directory.path, 'ora.db');
    try {
      var database = await factory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(ActivityDatabaseSchema.createActivitiesV1);
            await db.execute(ActivityDatabaseSchema.createOwnerStartIndex);
            await db.execute(ActivityDatabaseSchema.createOwnerCreatedIndex);
          },
        ),
      );
      await database.insert(
        'activities',
        _activity(id: 'ANDROID-V1', owner: '1001', start: 10).toMap(),
      );
      await database.close();

      database = await factory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: ActivityDatabaseSchema.currentVersion,
          onUpgrade: ActivityDatabaseSchema.upgrade,
        ),
      );
      final activityRows = await database.query('activities');
      final metadata = await database.query('schema_metadata');
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(activityRows.single['activityId'], 'ANDROID-V1');
      expect(
        metadata.singleWhere((row) => row['key'] == 'migrated_from')['value'],
        'android_v1',
      );
      final syncColumns = await database.rawQuery(
        'PRAGMA table_info(sync_queue)',
      );
      expect(
        syncColumns.map((row) => row['name']),
        containsAll([
          'retryCount',
          'payloadVersion',
          'payloadJson',
          'nextAttemptAtMillis',
          'serverStatus',
          'serverAckAtMillis',
          'lastErrorCode',
        ]),
      );
      expect(
        tables.map((row) => row['name']),
        containsAll([
          'run_sessions',
          'location_points',
          'run_events',
          'sync_queue',
        ]),
      );
      await database.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
