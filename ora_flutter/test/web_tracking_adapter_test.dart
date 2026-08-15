import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/data/web_tracking_adapter.dart';
import 'package:ora_flutter/features/tracking/domain/run_time_engine.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

class _FakePositionSource implements WebPositionSource {
  WebPositionFix? permissionFix;
  WebPositionException? permissionError;
  void Function(WebPositionFix)? onPosition;
  void Function(WebPositionException)? onError;
  final visibility = StreamController<bool>.broadcast();
  int watchCount = 0;
  int clearCount = 0;

  @override
  Future<WebPositionFix> currentPosition() async {
    if (permissionError case final error?) throw error;
    return permissionFix!;
  }

  @override
  int watchPosition(
    void Function(WebPositionFix fix) onPosition,
    void Function(WebPositionException error) onError,
  ) {
    this.onPosition = onPosition;
    this.onError = onError;
    return ++watchCount;
  }

  @override
  void clearWatch(int watchId) => clearCount++;

  @override
  bool isVisible = true;

  @override
  Stream<bool> get visibilityChanges => visibility.stream;
}

class _FakeClock implements TrackingClock {
  int monotonic = 1000;

  @override
  Future<NativeClockSnapshot> snapshot() async => NativeClockSnapshot(
    monotonicMillis: monotonic,
    epochMillis: 101000,
    bootEpochMillis: 100000,
  );
}

class _FakeWakeLock implements WebWakeLock {
  int acquired = 0;
  int released = 0;
  bool fail = false;

  @override
  Future<void> acquire() async {
    acquired++;
    if (fail) throw StateError('unsupported');
  }

  @override
  Future<void> release() async => released++;
}

const _fix = WebPositionFix(
  latitude: -6.2,
  longitude: 106.8,
  accuracyMeters: 8,
  epochMillis: 101000,
);

void main() {
  test('permission grant starts watch and maps browser fix safely', () async {
    final source = _FakePositionSource()..permissionFix = _fix;
    final wakeLock = _FakeWakeLock();
    final adapter = WebTrackingAdapter(
      positionSource: source,
      clock: _FakeClock(),
      wakeLock: wakeLock,
    );
    final eventFuture = adapter.events.first;

    expect(
      (await adapter.requestPermission()).permission,
      LocationPermissionState.precise,
    );
    await adapter.prepare();
    final preview = await eventFuture;
    expect(preview.type, 'location');
    expect(preview.sample?.provider, 'browser');
    expect(preview.sample?.providerMonotonicMillis, 1000);

    await adapter.start('S1');
    expect(source.watchCount, 2);
    expect(source.clearCount, 1);
    expect(wakeLock.acquired, 1);
  });

  test('permission denial is explicit and does not start a watch', () async {
    final source = _FakePositionSource()
      ..permissionError = const WebPositionException(
        WebPositionErrorKind.permissionDenied,
      );
    final adapter = WebTrackingAdapter(
      positionSource: source,
      clock: _FakeClock(),
      wakeLock: _FakeWakeLock(),
    );

    final status = await adapter.requestPermission();
    expect(status.permission, LocationPermissionState.denied);
    expect(status.errorCode, 'WEB_LOCATION_PERMISSION_DENIED');
    await expectLater(adapter.prepare(), throwsA(isA<Exception>()));
    expect(source.watchCount, 0);
  });

  test('pause/resume resets browser watch and wake lock is optional', () async {
    final source = _FakePositionSource()..permissionFix = _fix;
    final wakeLock = _FakeWakeLock()..fail = true;
    final adapter = WebTrackingAdapter(
      positionSource: source,
      clock: _FakeClock(),
      wakeLock: wakeLock,
    );
    await adapter.requestPermission();
    await adapter.prepare();
    await adapter.start('S1');
    await adapter.pause('S1');
    await adapter.resume('S1');
    await adapter.stop('S1');

    expect(source.watchCount, 3);
    expect(source.clearCount, 3);
    expect(wakeLock.acquired, 2);
    expect(wakeLock.released, 2);
    expect((await adapter.status()).serviceActive, isFalse);
  });

  test('temporary browser GPS error remains recoverable', () async {
    final source = _FakePositionSource()..permissionFix = _fix;
    final adapter = WebTrackingAdapter(
      positionSource: source,
      clock: _FakeClock(),
      wakeLock: _FakeWakeLock(),
    );
    await adapter.requestPermission();
    await adapter.prepare();
    final event = adapter.events.first;
    source.onError!(
      const WebPositionException(WebPositionErrorKind.unavailable),
    );
    expect((await event).type, 'providerUnavailable');
    expect(source.watchCount, 1);
  });
}
