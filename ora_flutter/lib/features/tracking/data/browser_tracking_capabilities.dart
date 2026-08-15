import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../domain/tracking_models.dart';
import '../domain/run_time_engine.dart';
import 'web_tracking_adapter.dart';

class BrowserPositionSource implements WebPositionSource {
  static final web.PositionOptions _options = web.PositionOptions(
    enableHighAccuracy: true,
    maximumAge: 3000,
    timeout: 12000,
  );

  @override
  Future<WebPositionFix> currentPosition() {
    final completer = Completer<WebPositionFix>();
    try {
      web.window.navigator.geolocation.getCurrentPosition(
        ((web.GeolocationPosition position) {
          if (!completer.isCompleted) completer.complete(_fix(position));
        }).toJS,
        ((web.GeolocationPositionError error) {
          if (!completer.isCompleted) completer.completeError(_error(error));
        }).toJS,
        _options,
      );
    } catch (_) {
      completer.completeError(
        const WebPositionException(WebPositionErrorKind.unsupported),
      );
    }
    return completer.future;
  }

  @override
  int watchPosition(
    void Function(WebPositionFix fix) onPosition,
    void Function(WebPositionException error) onError,
  ) {
    try {
      return web.window.navigator.geolocation.watchPosition(
        ((web.GeolocationPosition position) => onPosition(_fix(position))).toJS,
        ((web.GeolocationPositionError error) => onError(_error(error))).toJS,
        _options,
      );
    } catch (_) {
      throw const WebPositionException(WebPositionErrorKind.unsupported);
    }
  }

  @override
  void clearWatch(int watchId) {
    try {
      web.window.navigator.geolocation.clearWatch(watchId);
    } catch (_) {}
  }

  @override
  bool get isVisible => !web.document.hidden;

  @override
  Stream<bool> get visibilityChanges =>
      web.document.onVisibilityChange.map((_) => isVisible);

  static WebPositionFix _fix(web.GeolocationPosition position) =>
      WebPositionFix(
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        accuracyMeters: position.coords.accuracy,
        epochMillis: position.timestamp.toInt(),
      );

  static WebPositionException _error(web.GeolocationPositionError error) =>
      WebPositionException(switch (error.code) {
        web.GeolocationPositionError.PERMISSION_DENIED =>
          WebPositionErrorKind.permissionDenied,
        web.GeolocationPositionError.TIMEOUT => WebPositionErrorKind.timeout,
        _ => WebPositionErrorKind.unavailable,
      });
}

class BrowserTrackingClock implements TrackingClock {
  @override
  Future<NativeClockSnapshot> snapshot() async {
    final monotonic = web.window.performance.now().round();
    final bootEpoch = web.window.performance.timeOrigin.round();
    return NativeClockSnapshot(
      monotonicMillis: monotonic,
      epochMillis: bootEpoch + monotonic,
      bootEpochMillis: bootEpoch,
    );
  }
}

class BrowserWakeLock implements WebWakeLock {
  web.WakeLockSentinel? _sentinel;

  @override
  Future<void> acquire() async {
    final current = _sentinel;
    if (current != null && !current.released) return;
    _sentinel = await web.window.navigator.wakeLock.request('screen').toDart;
  }

  @override
  Future<void> release() async {
    final current = _sentinel;
    _sentinel = null;
    if (current != null && !current.released) await current.release().toDart;
  }
}
