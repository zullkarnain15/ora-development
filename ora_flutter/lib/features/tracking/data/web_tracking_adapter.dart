import 'dart:async';

import '../domain/run_time_engine.dart';
import '../domain/tracking_models.dart';
import 'native_tracking_adapter.dart';

class WebPositionFix {
  const WebPositionFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.epochMillis,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final int epochMillis;
}

enum WebPositionErrorKind {
  permissionDenied,
  unavailable,
  timeout,
  unsupported,
}

class WebPositionException implements Exception {
  const WebPositionException(this.kind);
  final WebPositionErrorKind kind;
}

abstract interface class WebPositionSource {
  Future<WebPositionFix> currentPosition();
  int watchPosition(
    void Function(WebPositionFix fix) onPosition,
    void Function(WebPositionException error) onError,
  );
  void clearWatch(int watchId);
  bool get isVisible;
  Stream<bool> get visibilityChanges;
}

abstract interface class WebWakeLock {
  Future<void> acquire();
  Future<void> release();
}

/// Browser lifecycle adapter. Validation, distance, duration and pace remain in
/// the shared tracking domain engine.
class WebTrackingAdapter
    implements TrackingNativeAdapter, DisposableTrackingAdapter {
  WebTrackingAdapter({
    required this.positionSource,
    required this.clock,
    required this.wakeLock,
  }) {
    _visibilitySubscription = positionSource.visibilityChanges.listen((
      visible,
    ) {
      if (visible && _state == _WebAdapterState.running) {
        unawaited(_tryAcquireWakeLock());
      }
    });
  }

  final WebPositionSource positionSource;
  final TrackingClock clock;
  final WebWakeLock wakeLock;
  final StreamController<NativeTrackingEvent> _events =
      StreamController<NativeTrackingEvent>.broadcast();

  StreamSubscription<bool>? _visibilitySubscription;
  _WebAdapterState _state = _WebAdapterState.idle;
  LocationPermissionState _permission = LocationPermissionState.notDetermined;
  WebPositionFix? _permissionFix;
  int? _watchId;
  String? _sessionId;
  int _sequence = 0;
  String? _lastErrorCode;

  @override
  Stream<NativeTrackingEvent> get events => _events.stream;

  @override
  Future<NativeClockSnapshot> snapshot() => clock.snapshot();

  @override
  Future<NativeTrackingStatus> status() async => _status();

  @override
  Future<NativeTrackingStatus> requestPermission() async {
    try {
      _permissionFix = await positionSource.currentPosition();
      _permission = LocationPermissionState.precise;
      _lastErrorCode = null;
    } on WebPositionException catch (error) {
      _lastErrorCode = _errorCode(error.kind);
      if (error.kind == WebPositionErrorKind.permissionDenied) {
        _permission = LocationPermissionState.denied;
      } else if (error.kind == WebPositionErrorKind.unsupported) {
        _permission = LocationPermissionState.restricted;
      }
    }
    return _status();
  }

  @override
  Future<void> prepare() async {
    if (_permission != LocationPermissionState.precise) {
      throw NativeTrackingFailure(
        _lastErrorCode ?? 'WEB_LOCATION_PERMISSION_REQUIRED',
        _permissionMessage,
      );
    }
    _state = _WebAdapterState.preview;
    _startWatch();
    final fix = _permissionFix;
    _permissionFix = null;
    if (fix != null) await _emitPosition(fix);
  }

  @override
  Future<void> cancelPrepare() async {
    if (_state == _WebAdapterState.preview) {
      _clearWatch();
      _state = _WebAdapterState.idle;
    }
  }

  @override
  Future<void> start(String sessionId) async {
    _clearWatch();
    _sessionId = sessionId;
    _state = _WebAdapterState.running;
    _startWatch();
    await _tryAcquireWakeLock();
  }

  @override
  Future<void> pause(String sessionId) async {
    _requireSession(sessionId);
    _clearWatch();
    _state = _WebAdapterState.paused;
    await _tryReleaseWakeLock();
  }

  @override
  Future<void> resume(String sessionId) async {
    _requireSession(sessionId);
    _state = _WebAdapterState.running;
    _startWatch();
    await _tryAcquireWakeLock();
  }

  @override
  Future<void> stop(String sessionId) async {
    _requireSession(sessionId);
    _clearWatch();
    _state = _WebAdapterState.idle;
    _sessionId = null;
    await _tryReleaseWakeLock();
  }

  @override
  Future<void> acknowledgePendingAction() async {}

  @override
  Future<void> disposeTrackingResources() async {
    _clearWatch();
    await _tryReleaseWakeLock();
    await _visibilitySubscription?.cancel();
    await _events.close();
  }

  void _startWatch() {
    _clearWatch();
    try {
      _watchId = positionSource.watchPosition(
        (fix) => unawaited(_emitPosition(fix)),
        _emitError,
      );
    } on WebPositionException catch (error) {
      _emitError(error);
    }
  }

  Future<void> _emitPosition(WebPositionFix fix) async {
    if (_state != _WebAdapterState.preview &&
        _state != _WebAdapterState.running) {
      return;
    }
    final now = await clock.snapshot();
    final providerMonotonic = (fix.epochMillis - now.bootEpochMillis)
        .clamp(0, now.monotonicMillis)
        .toInt();
    _lastErrorCode = null;
    _events.add(
      NativeTrackingEvent(
        type: 'location',
        sample: RawLocationSample(
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMeters: fix.accuracyMeters,
          providerMonotonicMillis: providerMonotonic,
          receivedMonotonicMillis: now.monotonicMillis,
          epochMillis: fix.epochMillis,
          sequence: ++_sequence,
          provider: 'browser',
        ),
      ),
    );
  }

  void _emitError(WebPositionException error) {
    _lastErrorCode = _errorCode(error.kind);
    if (error.kind == WebPositionErrorKind.permissionDenied) {
      _permission = LocationPermissionState.denied;
    }
    _events.add(
      NativeTrackingEvent(
        type: error.kind == WebPositionErrorKind.permissionDenied
            ? 'error'
            : 'providerUnavailable',
        code: _lastErrorCode,
        message: error.kind == WebPositionErrorKind.permissionDenied
            ? _permissionMessage
            : 'GPS signal is temporarily unavailable. ORA will keep trying.',
      ),
    );
  }

  NativeTrackingStatus _status() => NativeTrackingStatus(
    permission: _permission,
    locationEnabled:
        _permission != LocationPermissionState.restricted &&
        _lastErrorCode != 'WEB_GEOLOCATION_UNSUPPORTED',
    serviceActive: _state == _WebAdapterState.running,
    notificationGranted: true,
    sessionId: _sessionId,
    trackingState: _state.name.toUpperCase(),
    errorCode: _lastErrorCode,
  );

  void _clearWatch() {
    final id = _watchId;
    _watchId = null;
    if (id != null) positionSource.clearWatch(id);
  }

  void _requireSession(String sessionId) {
    if (_sessionId != sessionId) {
      throw const NativeTrackingFailure(
        'WEB_SESSION_MISMATCH',
        'The active browser run does not match this session.',
      );
    }
  }

  Future<void> _tryAcquireWakeLock() async {
    if (!positionSource.isVisible) return;
    try {
      await wakeLock.acquire();
    } catch (_) {
      // Optional progressive enhancement; tracking must remain available.
    }
  }

  Future<void> _tryReleaseWakeLock() async {
    try {
      await wakeLock.release();
    } catch (_) {
      // A browser can revoke the sentinel before ORA releases it.
    }
  }

  static String _errorCode(WebPositionErrorKind kind) => switch (kind) {
    WebPositionErrorKind.permissionDenied => 'WEB_LOCATION_PERMISSION_DENIED',
    WebPositionErrorKind.unavailable => 'WEB_POSITION_UNAVAILABLE',
    WebPositionErrorKind.timeout => 'WEB_POSITION_TIMEOUT',
    WebPositionErrorKind.unsupported => 'WEB_GEOLOCATION_UNSUPPORTED',
  };

  static const _permissionMessage =
      'Location permission is required. Allow Location in your browser settings.';
}

enum _WebAdapterState { idle, preview, running, paused }
