import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/run_time_engine.dart';
import '../domain/tracking_models.dart';

abstract interface class TrackingNativeAdapter implements TrackingClock {
  Stream<NativeTrackingEvent> get events;
  Future<NativeTrackingStatus> status();
  Future<NativeTrackingStatus> requestPermission();
  Future<void> prepare();
  Future<void> cancelPrepare();
  Future<void> start(String sessionId);
  Future<void> pause(String sessionId);
  Future<void> resume(String sessionId);
  Future<void> stop(String sessionId);
  Future<void> acknowledgePendingAction();
}

/// Optional lifecycle hook for adapters that own in-process resources. Native
/// Android tracking intentionally does not implement this because its service
/// must outlive the Flutter controller.
abstract interface class DisposableTrackingAdapter {
  Future<void> disposeTrackingResources();
}

class NativeTrackingFailure implements Exception {
  const NativeTrackingFailure(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'NativeTrackingFailure($code, $message)';
}

class MethodChannelTrackingAdapter implements TrackingNativeAdapter {
  const MethodChannelTrackingAdapter();

  static const contractVersion = 1;
  static const _methods = MethodChannel('ora/tracking/methods/v1');
  static const _eventChannel = EventChannel('ora/tracking/events/v1');

  @override
  Stream<NativeTrackingEvent> get events => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) => NativeTrackingEvent.fromMap(
          (event as Map).cast<Object?, Object?>(),
        ),
      );

  @override
  Future<NativeClockSnapshot> snapshot() async =>
      NativeClockSnapshot.fromMap(await _mapResult('clockSnapshot'));

  @override
  Future<NativeTrackingStatus> status() async =>
      NativeTrackingStatus.fromMap(await _mapResult('status'));

  @override
  Future<NativeTrackingStatus> requestPermission() async =>
      NativeTrackingStatus.fromMap(await _mapResult('requestPermission'));

  @override
  Future<void> prepare() => _simpleCommand('prepare');

  @override
  Future<void> cancelPrepare() => _simpleCommand('cancelPrepare');

  @override
  Future<void> start(String sessionId) => _command('start', sessionId);

  @override
  Future<void> pause(String sessionId) => _command('pause', sessionId);

  @override
  Future<void> resume(String sessionId) => _command('resume', sessionId);

  @override
  Future<void> stop(String sessionId) => _command('stop', sessionId);

  @override
  Future<void> acknowledgePendingAction() async {
    await _invoke<void>('acknowledgePendingAction');
  }

  Future<void> _command(String method, String sessionId) async {
    await _invoke<void>(method, {
      'contractVersion': contractVersion,
      'sessionId': sessionId,
      'diagnosticsEnabled': kDebugMode,
    });
  }

  Future<void> _simpleCommand(String method) async {
    await _invoke<void>(method, {'contractVersion': contractVersion});
  }

  Future<Map<Object?, Object?>> _mapResult(String method) async {
    final result = await _invoke<Object?>(method, {
      'contractVersion': contractVersion,
    });
    if (result is! Map) {
      throw const NativeTrackingFailure(
        'INVALID_NATIVE_RESPONSE',
        'Tracking service returned an invalid response.',
      );
    }
    return result.cast<Object?, Object?>();
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw NativeTrackingFailure(
        error.code,
        error.message ?? 'Native tracking failed.',
      );
    } on MissingPluginException {
      throw const NativeTrackingFailure(
        'NATIVE_ADAPTER_UNAVAILABLE',
        'Tracking is unavailable on this platform build.',
      );
    }
  }
}
