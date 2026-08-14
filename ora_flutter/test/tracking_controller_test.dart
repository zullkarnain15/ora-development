import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/tracking/application/tracking_controller.dart';
import 'package:ora_flutter/features/tracking/data/native_tracking_adapter.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

class _FakeNativeAdapter implements TrackingNativeAdapter {
  final controller = StreamController<NativeTrackingEvent>.broadcast();
  LocationPermissionState permission = LocationPermissionState.precise;
  bool serviceActive = false;
  int starts = 0;
  int monotonic = 1000;

  @override
  Stream<NativeTrackingEvent> get events => controller.stream;

  NativeTrackingStatus get _status => NativeTrackingStatus(
    permission: permission,
    locationEnabled: true,
    serviceActive: serviceActive,
    notificationGranted: true,
    sessionId: serviceActive ? 'native-session' : null,
    trackingState: serviceActive ? 'tracking' : 'stopped',
  );

  @override
  Future<NativeTrackingStatus> requestPermission() async => _status;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> cancelPrepare() async {}

  @override
  Future<NativeClockSnapshot> snapshot() async => NativeClockSnapshot(
    monotonicMillis: monotonic,
    epochMillis: 100000 + monotonic,
    bootEpochMillis: 100000,
  );

  @override
  Future<NativeTrackingStatus> status() async => _status;

  @override
  Future<void> start(String sessionId) async {
    starts++;
    serviceActive = true;
  }

  @override
  Future<void> pause(String sessionId) async => serviceActive = true;

  @override
  Future<void> resume(String sessionId) async => serviceActive = true;

  @override
  Future<void> stop(String sessionId) async => serviceActive = false;

  @override
  Future<void> acknowledgePendingAction() async {}

  Future<void> close() => controller.close();
}

final _user = UserSession(
  sessionToken: 'token',
  nik: '1001',
  nickname: 'RUNNER',
  divisionGuild: 'OPS',
  status: 'ACTIVE',
  expiresAt: DateTime.utc(2030),
);

Future<void> _prepareReady(
  TrackingController tracking,
  _FakeNativeAdapter native,
) async {
  await tracking.prepareGps();
  native.controller.add(
    const NativeTrackingEvent(
      type: 'location',
      sample: RawLocationSample(
        latitude: -6.2,
        longitude: 106.8,
        accuracyMeters: 5,
        providerMonotonicMillis: 1000,
        receivedMonotonicMillis: 1000,
        epochMillis: 101000,
        sequence: 1,
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(tracking.status, TrackingStatus.gpsReady);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'active UI duration advances after baseline without more GPS callbacks',
    () async {
      final native = _FakeNativeAdapter();
      final tracking = TrackingController(
        user: _user,
        store: MemoryActivityStore(),
        nativeAdapter: native,
      );
      await tracking.initialize();
      await _prepareReady(tracking, native);
      await tracking.start();
      expect(tracking.status, TrackingStatus.running);
      expect(tracking.activeDurationMillis, 0);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(tracking.activeDurationMillis, greaterThanOrEqualTo(900));
      tracking.dispose();
      await native.close();
    },
  );

  test(
    'approximate location is actionable and never starts the service',
    () async {
      final native = _FakeNativeAdapter()
        ..permission = LocationPermissionState.approximate;
      final tracking = TrackingController(
        user: _user,
        store: MemoryActivityStore(),
        nativeAdapter: native,
      );
      await tracking.initialize();
      await tracking.prepareGps();
      expect(tracking.status, TrackingStatus.idle);
      expect(tracking.message, contains('PRECISE LOCATION REQUIRED'));
      expect(native.starts, 0);
      tracking.dispose();
      await native.close();
    },
  );

  test(
    'GPS search times out and start anyway begins duration without distance',
    () async {
      final native = _FakeNativeAdapter();
      final tracking = TrackingController(
        user: _user,
        store: MemoryActivityStore(),
        nativeAdapter: native,
        gpsSearchTimeout: const Duration(milliseconds: 100),
      );
      await tracking.initialize();
      await tracking.prepareGps();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(tracking.gpsSearchTimedOut, isTrue);
      expect(tracking.canStartAnyway, isTrue);
      expect(tracking.distanceMeters, 0);

      await tracking.startAnyway();
      expect(tracking.status, TrackingStatus.running);
      expect(tracking.message, contains('WAITING FOR GPS'));
      expect(native.starts, 1);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(tracking.activeDurationMillis, greaterThan(0));
      expect(tracking.distanceMeters, 0);
      tracking.dispose();
      await native.close();
    },
  );

  test(
    'rapid pause and finish commands serialize with finish authoritative',
    () async {
      final native = _FakeNativeAdapter();
      final tracking = TrackingController(
        user: _user,
        store: MemoryActivityStore(),
        nativeAdapter: native,
      );
      await tracking.initialize();
      await _prepareReady(tracking, native);
      await tracking.start();
      native.controller.add(
        NativeTrackingEvent(
          type: 'location',
          sample: RawLocationSample(
            latitude: -6.2,
            longitude: 106.8,
            accuracyMeters: 5,
            providerMonotonicMillis: 1000,
            receivedMonotonicMillis: 1000,
            epochMillis: 101000,
            sequence: 1,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final pause = tracking.pause();
      final finish = tracking.finish();
      await Future.wait([pause, finish]);
      expect(tracking.status, TrackingStatus.finished);
      expect(native.serviceActive, isFalse);
      tracking.dispose();
      await native.close();
    },
  );
}
