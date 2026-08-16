import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/domain/gps_soak.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

RawLocationSample _sample({
  required int millis,
  required int sequence,
  double longitude = 106.8,
  double accuracy = 5,
  int ageMillis = 0,
}) => RawLocationSample(
  latitude: -6.2,
  longitude: longitude,
  accuracyMeters: accuracy,
  providerMonotonicMillis: millis - ageMillis,
  receivedMonotonicMillis: millis,
  epochMillis: 100000 + millis,
  sequence: sequence,
);

const _policy = GpsSoakPolicy(
  name: 'TEST',
  minValidSamples: 3,
  idealAccuracyMeters: 20,
  maximumReadyAccuracyMeters: 30,
  minimumSoakDuration: Duration(seconds: 2),
  maximumSoakDuration: Duration(seconds: 5),
  maximumSampleSpreadMeters: 20,
  minimumDegradedSamples: 2,
);

void main() {
  test('first GPS sample is not ready', () {
    final soak = GpsSoakEngine(policy: _policy);
    final result = soak.add(_sample(millis: 1000, sequence: 1));
    expect(result.state, GpsSoakState.stabilizing);
    expect(result.canStart, isFalse);
  });

  test('stable consecutive samples become ready after minimum duration', () {
    final soak = GpsSoakEngine(policy: _policy);
    soak.add(_sample(millis: 1000, sequence: 1));
    soak.add(_sample(millis: 2000, sequence: 2, longitude: 106.80001));
    final result = soak.add(
      _sample(millis: 3000, sequence: 3, longitude: 106.80002),
    );
    expect(result.state, GpsSoakState.ready);
    expect(result.validSampleCount, 3);
  });

  test('poor accuracy remains stabilizing and resets consecutive samples', () {
    final soak = GpsSoakEngine(policy: _policy);
    soak.add(_sample(millis: 1000, sequence: 1));
    final result = soak.add(_sample(millis: 2000, sequence: 2, accuracy: 31));
    expect(result.state, GpsSoakState.stabilizing);
    expect(result.validSampleCount, 0);
  });

  test('high positional drift remains stabilizing', () {
    final soak = GpsSoakEngine(policy: _policy);
    soak.add(_sample(millis: 1000, sequence: 1));
    soak.add(_sample(millis: 2000, sequence: 2, longitude: 106.801));
    final result = soak.add(
      _sample(millis: 3000, sequence: 3, longitude: 106.802),
    );
    expect(result.state, GpsSoakState.stabilizing);
    expect(result.sampleSpreadMeters, greaterThan(20));
  });

  test('timeout degrades gracefully only when recent samples are usable', () {
    final usable = GpsSoakEngine(policy: _policy);
    usable.add(_sample(millis: 1000, sequence: 1, accuracy: 25));
    usable.add(_sample(millis: 2000, sequence: 2, accuracy: 25));
    expect(usable.timeout(6000).state, GpsSoakState.degradedReady);

    final poor = GpsSoakEngine(policy: _policy);
    poor.add(_sample(millis: 1000, sequence: 1, accuracy: 40));
    expect(poor.timeout(6000).state, GpsSoakState.timedOut);
  });
}
