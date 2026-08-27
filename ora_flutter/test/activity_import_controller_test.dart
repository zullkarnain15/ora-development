import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/activity_import/application/activity_import_controller.dart';
import 'package:ora_flutter/features/activity_import/application/activity_import_inbox.dart';
import 'package:ora_flutter/features/activity_import/data/activity_import_bridge_api.dart';
import 'package:ora_flutter/features/activity_import/data/activity_ocr_engine.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_share_payload.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/dashboard/application/feature_controller.dart';
import 'package:ora_flutter/features/dashboard/data/ora_feature_api.dart';

class _UnusedFeatureApi implements OraFeatureApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _UnusedBridgeApi implements ActivityImportBridgeApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FixtureOcrEngine implements ActivityOcrEngine {
  const _FixtureOcrEngine(this.text);

  final String text;

  @override
  Future<String> recognize(ActivityShareImage image) async => text;
}

final _session = UserSession(
  sessionToken: 'fixture',
  nik: '1001',
  nickname: 'RUNNER',
  divisionGuild: 'OPS',
  status: 'ACTIVE',
  expiresAt: DateTime.utc(2030),
);

FinalActivity _stravaActivity({
  required String ref,
  required DateTime start,
  double distanceMeters = 8090,
  int durationSeconds = 3486,
}) => FinalActivity(
  activityId: importedActivityId(
    ownerNik: _session.nik,
    source: ActivityImportSource.strava,
    sourceRef: ref,
  ),
  ownerNik: _session.nik,
  nicknameSnapshot: _session.nickname,
  divisionGuildSnapshot: _session.divisionGuild,
  startDateTimeMillis: start.millisecondsSinceEpoch,
  endDateTimeMillis: start.millisecondsSinceEpoch + durationSeconds * 1000,
  distanceMeters: distanceMeters,
  activeDurationMillis: durationSeconds * 1000,
  averagePaceSecondsPerKm: 431,
  createdAtMillis: start.millisecondsSinceEpoch,
  source: 'STRAVA',
  sourceRef: ref,
  sourceUrl: 'https://strava.app.link/$ref',
);

ActivityImportController _controller({
  required ActivityStore store,
  required ActivityImportInbox inbox,
  required ActivityImportLaunch launch,
  ActivityOcrEngine ocr = const _FixtureOcrEngine(''),
}) => ActivityImportController(
  launch: launch,
  inbox: inbox,
  bridgeApi: _UnusedBridgeApi(),
  featureController: FeatureController(
    session: _session,
    api: _UnusedFeatureApi(),
    activityStore: store,
  ),
  ocrEngine: ocr,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'automatic OCR extracts metrics and releases shared image bytes',
    () async {
      final inbox = ActivityImportInbox();
      final launch = ActivityImportLaunch(
        payload: ActivitySharePayload(
          sharedUrl: 'https://www.strava.com/activities/123456',
          sourceHint: 'STRAVA',
          images: [
            ActivityShareImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              mimeType: 'image/jpeg',
            ),
          ],
          receivedAt: DateTime(2026, 8, 25),
        ),
      );
      await inbox.receive(launch);
      final controller = _controller(
        store: MemoryActivityStore(),
        inbox: inbox,
        launch: launch,
        ocr: const _FixtureOcrEngine(
          'Distance\n8.09 km\nMoving Time\n58:06\nAvg Pace\n7:11 /km',
        ),
      );

      await controller.initialize();

      expect(controller.draft?.distanceMeters, 8090);
      expect(controller.draft?.durationSeconds, 3486);
      expect(controller.draft?.detectedPaceSecondsPerKm, 431);
      expect(controller.draft?.calculatedPaceSecondsPerKm, 431);
      expect(controller.draft?.payload.images, isEmpty);
      expect(inbox.current?.payload?.images, isEmpty);
      controller.featureController.dispose();
      controller.dispose();
      inbox.dispose();
    },
  );

  test(
    'OCR failure blocks save with the required share-again message',
    () async {
      final inbox = ActivityImportInbox();
      final launch = ActivityImportLaunch(
        payload: ActivitySharePayload(
          sharedUrl: 'https://www.strava.com/activities/123456',
          sourceHint: 'STRAVA',
          images: [
            ActivityShareImage(
              bytes: Uint8List.fromList([1]),
              mimeType: 'image/jpeg',
            ),
          ],
          receivedAt: DateTime(2026, 8, 25),
        ),
      );
      final controller = _controller(
        store: MemoryActivityStore(),
        inbox: inbox,
        launch: launch,
        ocr: const _FixtureOcrEngine('Strava activity'),
      );

      await controller.initialize();
      expect(await controller.save(), isFalse);
      expect(
        controller.message,
        'ACTIVITY DATA COULD NOT BE READ – SHARE AGAIN FROM STRAVA',
      );
      controller.featureController.dispose();
      controller.dispose();
      inbox.dispose();
    },
  );

  test(
    'same SourceRef is exact duplicate even with a different start time',
    () async {
      final store = MemoryActivityStore();
      await store.insert(
        _stravaActivity(ref: 'SameLink', start: DateTime(2026, 8, 25, 6)),
      );
      final inbox = ActivityImportInbox();
      final launch = ActivityImportLaunch(
        payload: ActivitySharePayload(
          sharedText: 'Strava\n8.09 km\n58:06',
          sharedUrl: 'https://strava.app.link/SameLink',
          receivedAt: DateTime(2026, 8, 25),
        ),
      );
      final controller = _controller(
        store: store,
        inbox: inbox,
        launch: launch,
      );

      await controller.initialize();
      expect(controller.draft?.exactDuplicate, isTrue);
      expect(await controller.save(), isFalse);
      expect(controller.message, 'DUPLICATE ACTIVITY – ALREADY SAVED');
      expect(
        importedActivityId(
          ownerNik: _session.nik,
          source: ActivityImportSource.strava,
          sourceRef: 'SameLink',
        ),
        _stravaActivity(
          ref: 'SameLink',
          start: DateTime(2025, 1, 1),
        ).activityId,
      );
      controller.featureController.dispose();
      controller.dispose();
      inbox.dispose();
    },
  );

  test(
    'different short link with matching fingerprint is possible duplicate',
    () async {
      final store = MemoryActivityStore();
      await store.insert(
        _stravaActivity(ref: 'OldShort', start: DateTime(2026, 8, 25, 6)),
      );
      final inbox = ActivityImportInbox();
      final launch = ActivityImportLaunch(
        payload: ActivitySharePayload(
          sharedText: 'Strava\n8.10 km\n58:45',
          sharedUrl: 'https://strava.app.link/NewShort',
          receivedAt: DateTime(2026, 8, 25),
        ),
      );
      final controller = _controller(
        store: store,
        inbox: inbox,
        launch: launch,
      );

      await controller.initialize();
      expect(await controller.save(), isFalse);
      expect(controller.draft?.exactDuplicate, isFalse);
      expect(controller.draft?.possibleDuplicate, isTrue);
      expect(controller.message, 'POSSIBLE DUPLICATE – SAVE ANYWAY?');
      controller.featureController.dispose();
      controller.dispose();
      inbox.dispose();
    },
  );

  test(
    'save keeps preview open and persists SourceRef and SourceUrl locally',
    () async {
      final store = MemoryActivityStore();
      final inbox = ActivityImportInbox();
      final launch = ActivityImportLaunch(
        payload: ActivitySharePayload(
          sharedText: 'Strava\n5.00 km\n30:00\n6:00 /km',
          sharedUrl: 'https://www.strava.com/activities/998877',
          receivedAt: DateTime(2026, 8, 25, 6, 10),
        ),
      );
      await inbox.receive(launch);
      final controller = _controller(
        store: store,
        inbox: inbox,
        launch: launch,
      );

      await controller.initialize();
      expect(await controller.save(), isTrue);
      expect(controller.phase, ActivityImportPhase.saved);
      expect(controller.message, 'SAVED LOCALLY – SYNC PENDING');
      expect(inbox.current, isNotNull);
      final stored = (await store.newestFirst(_session.nik)).single;
      expect(stored.source, 'STRAVA');
      expect(stored.sourceRef, '998877');
      expect(stored.sourceUrl, 'https://www.strava.com/activities/998877');
      expect(
        stored.startDateTimeMillis,
        DateTime(2026, 8, 25, 6, 10).millisecondsSinceEpoch,
      );
      controller.featureController.dispose();
      controller.dispose();
      inbox.dispose();
    },
  );
}
