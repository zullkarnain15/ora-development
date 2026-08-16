import 'dart:math' as math;

import 'location_engine.dart';
import 'tracking_models.dart';

enum GpsSoakState { searching, stabilizing, ready, degradedReady, timedOut }

class GpsSoakPolicy {
  const GpsSoakPolicy({
    required this.name,
    required this.minValidSamples,
    required this.idealAccuracyMeters,
    required this.maximumReadyAccuracyMeters,
    required this.minimumSoakDuration,
    required this.maximumSoakDuration,
    required this.maximumSampleSpreadMeters,
    this.maxSampleAge = const Duration(seconds: 15),
    this.minimumDegradedSamples = 2,
  });

  final String name;
  final int minValidSamples;
  final double idealAccuracyMeters;
  final double maximumReadyAccuracyMeters;
  final Duration minimumSoakDuration;
  final Duration maximumSoakDuration;
  final double maximumSampleSpreadMeters;
  final Duration maxSampleAge;
  final int minimumDegradedSamples;

  static const android = GpsSoakPolicy(
    name: 'ANDROID_LIGHT',
    minValidSamples: 3,
    idealAccuracyMeters: 20,
    maximumReadyAccuracyMeters: 30,
    minimumSoakDuration: Duration(seconds: 3),
    maximumSoakDuration: Duration(seconds: 20),
    maximumSampleSpreadMeters: 35,
  );

  static const web = GpsSoakPolicy(
    name: 'WEB_CONSERVATIVE',
    minValidSamples: 5,
    idealAccuracyMeters: 20,
    maximumReadyAccuracyMeters: 35,
    minimumSoakDuration: Duration(seconds: 5),
    maximumSoakDuration: Duration(seconds: 20),
    maximumSampleSpreadMeters: 45,
    maxSampleAge: Duration(seconds: 30),
    minimumDegradedSamples: 3,
  );
}

class GpsSoakResult {
  const GpsSoakResult({
    required this.state,
    required this.sampleCount,
    required this.validSampleCount,
    required this.elapsed,
    required this.sampleSpreadMeters,
    this.latestSample,
  });

  final GpsSoakState state;
  final int sampleCount;
  final int validSampleCount;
  final Duration elapsed;
  final double sampleSpreadMeters;
  final RawLocationSample? latestSample;

  bool get canStart =>
      state == GpsSoakState.ready || state == GpsSoakState.degradedReady;
}

class GpsSoakEngine {
  GpsSoakEngine({required this.policy});

  final GpsSoakPolicy policy;
  final List<RawLocationSample> _validSamples = [];
  int _sampleCount = 0;
  int? _startedAtMillis;
  int? _lastProviderMillis;
  GpsSoakState _state = GpsSoakState.searching;

  void reset() {
    _validSamples.clear();
    _sampleCount = 0;
    _startedAtMillis = null;
    _lastProviderMillis = null;
    _state = GpsSoakState.searching;
  }

  GpsSoakResult add(RawLocationSample sample) {
    _sampleCount += 1;
    _startedAtMillis ??= sample.receivedMonotonicMillis;
    final elapsed = _elapsed(sample.receivedMonotonicMillis);
    final accuracy = sample.accuracyMeters;
    final age = sample.receivedMonotonicMillis - sample.providerMonotonicMillis;
    final coordinatesValid =
        sample.latitude.isFinite &&
        sample.longitude.isFinite &&
        sample.latitude >= -90 &&
        sample.latitude <= 90 &&
        sample.longitude >= -180 &&
        sample.longitude <= 180;
    final timestampValid =
        age >= 0 &&
        age <= policy.maxSampleAge.inMilliseconds &&
        (_lastProviderMillis == null ||
            sample.providerMonotonicMillis > _lastProviderMillis!);
    _lastProviderMillis = math.max(
      _lastProviderMillis ?? -1,
      sample.providerMonotonicMillis,
    );
    final qualityValid =
        accuracy != null &&
        accuracy.isFinite &&
        accuracy > 0 &&
        accuracy <= policy.maximumReadyAccuracyMeters;

    if (!coordinatesValid || !timestampValid || !qualityValid) {
      _validSamples.clear();
      _state = GpsSoakState.stabilizing;
      return _result(elapsed, sample);
    }

    _validSamples.add(sample);
    if (_validSamples.length > policy.minValidSamples) {
      _validSamples.removeAt(0);
    }
    final spread = _spreadMeters();
    final allIdeal = _validSamples.every(
      (point) => point.accuracyMeters! <= policy.idealAccuracyMeters,
    );
    final enoughSamples = _validSamples.length >= policy.minValidSamples;
    final enoughTime = elapsed >= policy.minimumSoakDuration;
    if (enoughSamples &&
        enoughTime &&
        allIdeal &&
        spread <= policy.maximumSampleSpreadMeters) {
      _state = GpsSoakState.ready;
    } else {
      _state = GpsSoakState.stabilizing;
    }
    return _result(elapsed, sample);
  }

  GpsSoakResult timeout(int nowMonotonicMillis) {
    final elapsed = _elapsed(nowMonotonicMillis);
    final spread = _spreadMeters();
    final latest = _validSamples.isEmpty ? null : _validSamples.last;
    final usable =
        _validSamples.length >= policy.minimumDegradedSamples &&
        latest != null &&
        latest.accuracyMeters! <= policy.maximumReadyAccuracyMeters &&
        spread <= policy.maximumSampleSpreadMeters;
    _state = usable ? GpsSoakState.degradedReady : GpsSoakState.timedOut;
    return _result(elapsed, latest);
  }

  GpsSoakResult _result(Duration elapsed, RawLocationSample? latest) =>
      GpsSoakResult(
        state: _state,
        sampleCount: _sampleCount,
        validSampleCount: _validSamples.length,
        elapsed: elapsed,
        sampleSpreadMeters: _spreadMeters(),
        latestSample: latest,
      );

  Duration _elapsed(int nowMillis) => Duration(
    milliseconds: math.max(0, nowMillis - (_startedAtMillis ?? nowMillis)),
  );

  double _spreadMeters() {
    var maximum = 0.0;
    for (var first = 0; first < _validSamples.length; first += 1) {
      for (var second = first + 1; second < _validSamples.length; second += 1) {
        maximum = math.max(
          maximum,
          geodesicDistanceMeters(_validSamples[first], _validSamples[second]),
        );
      }
    }
    return maximum;
  }
}
