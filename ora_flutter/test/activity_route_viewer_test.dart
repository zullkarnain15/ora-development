import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity/domain/activity_sync.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/activity/presentation/activity_route_viewer.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

ActivityRoutePoint _point(double lat, double lon, int sequence) =>
    ActivityRoutePoint(latitude: lat, longitude: lon, sequence: sequence);

FinalActivity _summaryActivity(String id) => FinalActivity(
  activityId: id,
  ownerNik: '1001',
  nicknameSnapshot: null,
  divisionGuildSnapshot: null,
  startDateTimeMillis: 1000,
  endDateTimeMillis: 2000,
  distanceMeters: 1000,
  activeDurationMillis: 300000,
  averagePaceSecondsPerKm: 300,
  createdAtMillis: 2000,
  syncStatus: ActivitySyncStatus.synced,
);

RunSession _run() => const RunSession(
  sessionId: 'ROUTE',
  ownerNik: '1001',
  nicknameSnapshot: 'RUNNER',
  divisionGuildSnapshot: 'OPS',
  status: TrackingStatus.finalizing,
  policyVersion: 2,
  startEpochMillis: 1000,
  endEpochMillis: 3000,
  startMonotonicMillis: 10,
  bootEpochMillis: 990,
  activeAccumulatedMillis: 2000,
  lastCheckpointMonotonicMillis: 2000,
  distanceMeters: 20,
  acceptedPoints: 2,
  rejectedPoints: 0,
  createdAtMillis: 1000,
  updatedAtMillis: 3000,
);

PersistedPointDecision _accepted(int sequence) => PersistedPointDecision(
  sessionId: 'ROUTE',
  sample: RawLocationSample(
    latitude: -6.2 + sequence / 10000,
    longitude: 106.8 + sequence / 10000,
    accuracyMeters: 5,
    providerMonotonicMillis: sequence * 1000,
    receivedMonotonicMillis: sequence * 1000,
    epochMillis: sequence * 1000,
    sequence: sequence,
  ),
  decision: const LocationDecision(
    type: LocationDecisionType.accepted,
    segmentMeters: 10,
  ),
);

void main() {
  const size = Size(300, 200);

  test(
    'route projection handles empty, one, duplicate and straight routes',
    () {
      expect(ActivityRouteProjector.project(const [], size), isEmpty);
      expect(
        ActivityRouteProjector.project([_point(1, 1, 1)], size).single,
        const Offset(150, 100),
      );
      final duplicate = ActivityRouteProjector.project([
        _point(1, 1, 1),
        _point(1, 1, 2),
      ], size);
      expect(
        duplicate.every((point) => point == const Offset(150, 100)),
        isTrue,
      );
      final vertical = ActivityRouteProjector.project([
        _point(1, 1, 1),
        _point(2, 1, 2),
      ], size);
      expect(vertical.first.dx, vertical.last.dx);
      expect(vertical.first.dy, isNot(vertical.last.dy));
      final horizontal = ActivityRouteProjector.project([
        _point(1, 1, 1),
        _point(1, 2, 2),
      ], size);
      expect(horizontal.first.dy, horizontal.last.dy);
      expect(horizontal.first.dx, isNot(horizontal.last.dx));
    },
  );

  test('large route is bounded and source points remain unchanged', () {
    final source = List.generate(
      5000,
      (index) => _point(index / 1000, index / 2000, index),
    );
    final before = List<ActivityRoutePoint>.of(source);
    final projected = ActivityRouteProjector.project(source, size);
    expect(projected, hasLength(1200));
    expect(source, orderedEquals(before));
    expect(projected.every((p) => p.dx >= 0 && p.dx <= size.width), isTrue);
    expect(projected.every((p) => p.dy >= 0 && p.dy <= size.height), isTrue);
  });

  testWidgets('route painter renders without exception', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomPaint(
          size: size,
          painter: ActivityRoutePainter([
            _point(-6.2, 106.8, 1),
            _point(-6.21, 106.81, 2),
          ]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('backend-only activity reports route unavailable without crash', (
    tester,
  ) async {
    final store = MemoryActivityStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityRouteViewer(
            store: store,
            activity: _summaryActivity('SERVER-ONLY'),
            ownerNik: '1001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ROUTE DATA NOT AVAILABLE ON THIS DEVICE'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('local activity still renders its local route', (tester) async {
    final store = MemoryActivityStore();
    final run = _run();
    await store.createRun(
      run,
      const RunEvent(
        eventId: 'E1',
        sessionId: 'ROUTE',
        type: 'START',
        monotonicMillis: 10,
        epochMillis: 1000,
      ),
    );
    await store.recordPointDecision(run, _accepted(1));
    await store.recordPointDecision(run, _accepted(2));
    final activity = await store.finalizeRun(run);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: ActivityRouteViewer(
                store: store,
                activity: activity,
                ownerNik: '1001',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activity_route_canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed synced local data makes route unavailable', (
    tester,
  ) async {
    final store = MemoryActivityStore();
    final run = _run();
    await store.createRun(
      run,
      const RunEvent(
        eventId: 'E1',
        sessionId: 'ROUTE',
        type: 'START',
        monotonicMillis: 10,
        epochMillis: 1000,
      ),
    );
    await store.recordPointDecision(run, _accepted(1));
    final activity = await store.finalizeRun(run);
    final queue = (await store.dueSync('1001', 100000, force: true)).single;
    await store.acknowledgeSync(
      queue.queueId,
      queue.activityId,
      '1001',
      serverStatus: 'SAVED',
      acknowledgedAtMillis: 100000,
    );
    await store.removeLocalData(activity.activityId, '1001');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityRouteViewer(
            store: store,
            activity: _summaryActivity(activity.activityId),
            ownerNik: '1001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ROUTE DATA NOT AVAILABLE ON THIS DEVICE'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('activity_route_canvas')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
