import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/domain/final_distance_reconciler.dart';
import 'package:ora_flutter/features/tracking/domain/location_engine.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

const _originLat = -6.2;
const _originLon = 106.8;

RawLocationSample _sample(
  double east,
  double north,
  int sequence, {
  double accuracy = 5,
}) {
  const metersPerDegreeLat = 111195.0;
  final metersPerDegreeLon =
      metersPerDegreeLat * math.cos(_originLat * math.pi / 180);
  return RawLocationSample(
    latitude: _originLat + north / metersPerDegreeLat,
    longitude: _originLon + east / metersPerDegreeLon,
    accuracyMeters: accuracy,
    providerMonotonicMillis: sequence * 1000,
    receivedMonotonicMillis: sequence * 1000,
    epochMillis: 100000 + sequence * 1000,
    sequence: sequence,
  );
}

List<PersistedPointDecision> _segment(
  List<(double, double, double)> coordinates, {
  int sequenceOffset = 0,
}) {
  final result = <PersistedPointDecision>[];
  RawLocationSample? previous;
  for (var index = 0; index < coordinates.length; index += 1) {
    final value = coordinates[index];
    final sample = _sample(
      value.$1,
      value.$2,
      sequenceOffset + index + 1,
      accuracy: value.$3,
    );
    final segment = previous == null
        ? 0.0
        : geodesicDistanceMeters(previous, sample);
    result.add(
      PersistedPointDecision(
        sessionId: 'S1',
        sample: sample,
        decision: LocationDecision(
          type: previous == null
              ? LocationDecisionType.baseline
              : LocationDecisionType.accepted,
          segmentMeters: segment,
        ),
      ),
    );
    previous = sample;
  }
  return result;
}

void _expectNoMaterialCorrection(List<PersistedPointDecision> points) {
  final result = const FinalDistanceReconciler().reconcile(points);
  expect(
    result.finalDistanceMeters,
    closeTo(result.integratedDistanceMeters, .01),
  );
  expect(result.suspicious, isFalse);
}

void main() {
  test('clean straight track is a no-op', () {
    _expectNoMaterialCorrection(
      _segment([(0, 0, 5), (100, 0, 5), (200, 0, 5)]),
    );
  });

  test('clean synthetic 12 km track is a no-op', () {
    final coordinates = <(double, double, double)>[
      for (var index = 0; index <= 120; index += 1)
        (index * 100.0, math.sin(index / 8) * 20, 5),
    ];
    final result = const FinalDistanceReconciler().reconcile(
      _segment(coordinates),
    );
    expect(result.integratedDistanceMeters, greaterThan(11900));
    expect(
      result.finalDistanceMeters,
      closeTo(result.integratedDistanceMeters, .01),
    );
  });

  test('single high-confidence lateral spike is corrected', () {
    final points = _segment([
      for (var index = 0; index <= 10; index += 1) (index * 100.0, 0.0, 5.0),
      (1030, 120, 35),
      (1100, 0, 5),
      for (var index = 12; index <= 20; index += 1) (index * 100.0, 0.0, 5.0),
    ]);
    final result = const FinalDistanceReconciler().reconcile(points);
    expect(result.correctedSpikeCount, 1);
    expect(
      result.finalDistanceMeters,
      lessThan(result.integratedDistanceMeters),
    );
    expect(result.suspicious, isFalse);
  });

  test('90-degree real corner is preserved', () {
    _expectNoMaterialCorrection(
      _segment([(0, 0, 5), (100, 0, 5), (100, 100, 5)]),
    );
  });

  test('U-turn and out-and-back geometry are preserved', () {
    _expectNoMaterialCorrection(_segment([(0, 0, 5), (100, 0, 5), (0, 0, 5)]));
    _expectNoMaterialCorrection(
      _segment([(0, 0, 5), (100, 0, 5), (200, 0, 5), (100, 0, 5), (0, 0, 5)]),
    );
  });

  test('curved route and switchback are preserved', () {
    _expectNoMaterialCorrection(
      _segment([(0, 0, 5), (50, 30, 5), (90, 80, 5), (100, 140, 5)]),
    );
    _expectNoMaterialCorrection(
      _segment([(0, 0, 5), (80, 30, 5), (20, 60, 5), (100, 90, 5)]),
    );
  });

  test('stationary poor-accuracy drift is reduced', () {
    final points = _segment([
      (0, 0, 5),
      (500, 0, 5),
      (1000, 0, 5),
      (2000, 0, 25),
      (2010, 0, 25),
      (2000, 10, 25),
      (1990, 0, 25),
      (2000, -10, 25),
      (2000, 0, 25),
      (2500, 0, 5),
    ], sequenceOffset: 10);
    final result = const FinalDistanceReconciler().reconcile(points);
    expect(result.reducedDriftClusterCount, 1);
    expect(
      result.finalDistanceMeters,
      lessThan(result.integratedDistanceMeters),
    );
  });

  test('slow real movement and short clean route are preserved', () {
    _expectNoMaterialCorrection(
      _segment([
        (0, 0, 5),
        (2, 0, 5),
        (4, 0, 5),
        (6, 0, 5),
        (8, 0, 5),
        (10, 0, 5),
      ]),
    );
    _expectNoMaterialCorrection(_segment([(0, 0, 5), (15, 0, 5), (30, 0, 5)]));
  });

  test('pause relocation is segmented and never connected', () {
    final beforePause = _segment([(0, 0, 5), (100, 0, 5)]);
    final afterResume = _segment([
      (5000, 5000, 5),
      (5100, 5000, 5),
    ], sequenceOffset: 10);
    final result = const FinalDistanceReconciler().reconcile([
      ...beforePause,
      ...afterResume,
    ]);
    expect(result.integratedDistanceMeters, closeTo(200, 1));
    expect(result.finalDistanceMeters, closeTo(200, 1));
  });

  test('large low-confidence correction trips safety guard', () {
    final drift = _segment([
      (0, 0, 25),
      (10, 0, 25),
      (0, 10, 25),
      (-10, 0, 25),
      (0, -10, 25),
      (0, 0, 25),
    ]);
    final result = const FinalDistanceReconciler().reconcile(drift);
    expect(result.suspicious, isTrue);
    expect(result.flags, contains('RECONCILIATION_SUSPICIOUS'));
    expect(result.finalDistanceMeters, result.integratedDistanceMeters);
  });
}
