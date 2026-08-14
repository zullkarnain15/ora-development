import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/domain/location_engine.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

const _lat = -6.2;
const _lon = 106.8;

RawLocationSample _point({
  double latitude = _lat,
  double longitude = _lon,
  double? accuracy = 5,
  required int seconds,
  int? receivedSeconds,
  int sequence = 1,
}) => RawLocationSample(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: accuracy,
  providerMonotonicMillis: seconds * 1000,
  receivedMonotonicMillis: (receivedSeconds ?? seconds) * 1000,
  epochMillis: seconds * 1000,
  sequence: sequence,
  provider: 'fixture',
);

void main() {
  group('Android parity GPS policy', () {
    late RunLocationEngine engine;

    setUp(() {
      engine = RunLocationEngine(policy: TrackingPolicy.androidParityV1)
        ..startNewSession();
    });

    test('duplicate coordinate adds no distance', () {
      engine.process(_point(seconds: 1));
      final result = engine.process(_point(seconds: 2, sequence: 2));
      expect(result.reason, LocationRejectReason.duplicateCoordinate);
      expect(engine.totalDistanceMeters, 0);
    });

    test('invalid coordinates are rejected', () {
      final result = engine.process(_point(latitude: 91, seconds: 1));
      expect(result.reason, LocationRejectReason.invalidCoordinates);
    });

    test('missing and poor accuracy are rejected without a baseline', () {
      expect(
        engine.process(_point(accuracy: null, seconds: 1)).reason,
        LocationRejectReason.missingAccuracy,
      );
      expect(
        engine.process(_point(accuracy: 31, seconds: 2, sequence: 2)).reason,
        LocationRejectReason.poorAccuracy,
      );
      expect(engine.totalDistanceMeters, 0);
    });

    test('stale, future, and out-of-order fixes are rejected', () {
      expect(
        engine.process(_point(seconds: 1, receivedSeconds: 17)).reason,
        LocationRejectReason.staleLocation,
      );
      expect(
        engine
            .process(_point(seconds: 4, receivedSeconds: 3, sequence: 2))
            .reason,
        LocationRejectReason.futureTimestamp,
      );
      engine.process(_point(seconds: 5, sequence: 3));
      expect(
        engine.process(_point(seconds: 5, sequence: 4)).reason,
        LocationRejectReason.outOfOrder,
      );
    });

    test('implausible jump and stationary jitter add no distance', () {
      engine.process(_point(seconds: 1));
      expect(
        engine
            .process(_point(longitude: _lon + .001, seconds: 2, sequence: 2))
            .reason,
        LocationRejectReason.implausibleSpeed,
      );
      expect(
        engine
            .process(_point(longitude: _lon + .000005, seconds: 3, sequence: 3))
            .reason,
        LocationRejectReason.jitter,
      );
      expect(engine.totalDistanceMeters, 0);
    });

    test('valid consecutive points accumulate geodesic distance', () {
      engine.process(_point(seconds: 1));
      final result = engine.process(
        _point(longitude: _lon + .00003, seconds: 2, sequence: 2),
      );
      expect(result.type, LocationDecisionType.accepted);
      expect(engine.totalDistanceMeters, greaterThan(3));
      expect(engine.diagnostics.acceptedPoints, 2);
    });

    test('long GPS gap creates a new baseline and adds no jump', () {
      engine.process(_point(seconds: 1));
      final result = engine.process(
        _point(longitude: _lon + .01, seconds: 12, sequence: 2),
      );
      expect(result.type, LocationDecisionType.reentryBaseline);
      expect(engine.totalDistanceMeters, 0);
    });

    test('pause ignores movement and resume requires a fresh baseline', () {
      engine.process(_point(seconds: 1));
      engine.pause();
      expect(
        engine
            .process(_point(longitude: _lon + .01, seconds: 2, sequence: 2))
            .type,
        LocationDecisionType.ignored,
      );
      engine.resume();
      expect(
        engine
            .process(_point(longitude: _lon + .01, seconds: 3, sequence: 3))
            .type,
        LocationDecisionType.baseline,
      );
      expect(engine.totalDistanceMeters, 0);
    });
  });

  test('current policy confirms continuity after an implausible jump', () {
    final engine = RunLocationEngine()..startNewSession();
    engine.process(_point(seconds: 1));
    expect(
      engine
          .process(_point(longitude: _lon + .001, seconds: 2, sequence: 2))
          .reason,
      LocationRejectReason.implausibleSpeed,
    );
    final confirmed = engine.process(
      _point(longitude: _lon + .00101, seconds: 3, sequence: 3),
    );
    expect(confirmed.type, LocationDecisionType.reentryBaseline);
    expect(engine.totalDistanceMeters, 0);
  });

  test('quality bands and policy versions are explicit fixtures', () {
    expect(TrackingPolicy.androidParityV1.version, 1);
    expect(TrackingPolicy.current.version, 2);
    expect(
      _point(accuracy: 8, seconds: 1).quality(TrackingPolicy.current),
      GpsQuality.excellent,
    );
    expect(
      _point(accuracy: 18, seconds: 1).quality(TrackingPolicy.current),
      GpsQuality.good,
    );
    expect(
      _point(accuracy: 28, seconds: 1).quality(TrackingPolicy.current),
      GpsQuality.weak,
    );
    expect(
      _point(accuracy: 60, seconds: 1).quality(TrackingPolicy.current),
      GpsQuality.poor,
    );
  });

  test('pace is unavailable below 20 m and matches Android fixtures', () {
    expect(averagePaceSecondsPerKm(10000, 5), isNull);
    expect(averagePaceSecondsPerKm(6 * 60 * 1000, 1000), 360);
    expect(averagePaceSecondsPerKm(30 * 60 * 1000, 5000), 360);
    expect(averagePaceSecondsPerKm(55 * 60 * 1000, 10000), 330);
  });
}
