import 'dart:math' as math;

import 'tracking_models.dart';

class RunLocationEngine {
  RunLocationEngine({this.policy = TrackingPolicy.current});

  final TrackingPolicy policy;
  double totalDistanceMeters = 0;
  TrackingDiagnostics diagnostics = const TrackingDiagnostics();
  bool _tracking = false;
  RawLocationSample? _baseline;
  RawLocationSample? _continuityCandidate;
  int _continuityConfirmations = 0;
  int _lastProcessedMonotonicMillis = -1;

  void startNewSession() {
    totalDistanceMeters = 0;
    diagnostics = const TrackingDiagnostics();
    _tracking = true;
    _resetContinuity();
  }

  void restore({required double distanceMeters}) {
    totalDistanceMeters = math.max(0, distanceMeters);
    _tracking = true;
    _resetContinuity();
  }

  void pause() {
    _tracking = false;
    _resetContinuity();
  }

  void resume() {
    _tracking = true;
    _resetContinuity();
  }

  void stop() {
    _tracking = false;
    _resetContinuity();
  }

  LocationDecision process(RawLocationSample point) {
    if (!_tracking) {
      return const LocationDecision(
        type: LocationDecisionType.ignored,
        reason: LocationRejectReason.notTracking,
      );
    }
    diagnostics = diagnostics.copyWith(
      latestAccuracyMeters: point.accuracyMeters,
      firstRawCallbackLatencyMillis: diagnostics.firstRawCallbackLatencyMillis,
    );
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      return _reject(LocationRejectReason.invalidCoordinates);
    }
    final age = point.receivedMonotonicMillis - point.providerMonotonicMillis;
    if (age < 0) return _reject(LocationRejectReason.futureTimestamp);
    if (age > policy.maxLocationAgeMillis) {
      return _reject(LocationRejectReason.staleLocation);
    }
    if (point.providerMonotonicMillis <= _lastProcessedMonotonicMillis) {
      return _reject(LocationRejectReason.outOfOrder);
    }
    _lastProcessedMonotonicMillis = point.providerMonotonicMillis;

    final accuracy = point.accuracyMeters;
    if (accuracy == null || !accuracy.isFinite || accuracy <= 0) {
      return _reject(LocationRejectReason.missingAccuracy);
    }
    if (accuracy > policy.maxAccuracyMeters) {
      return _reject(LocationRejectReason.poorAccuracy);
    }

    final previous = _baseline;
    if (previous == null) {
      _baseline = point;
      _continuityCandidate = null;
      _accept();
      return const LocationDecision(type: LocationDecisionType.baseline);
    }
    final elapsed =
        point.providerMonotonicMillis - previous.providerMonotonicMillis;
    if (elapsed > policy.reentryGapMillis) {
      _baseline = point;
      _continuityCandidate = null;
      _accept();
      return const LocationDecision(type: LocationDecisionType.reentryBaseline);
    }
    if (point.latitude == previous.latitude &&
        point.longitude == previous.longitude) {
      _baseline = point;
      return _reject(LocationRejectReason.duplicateCoordinate);
    }

    final candidate = _continuityCandidate;
    if (candidate != null) {
      final candidateAge =
          point.providerMonotonicMillis - candidate.providerMonotonicMillis;
      final candidateDistance = geodesicDistanceMeters(candidate, point);
      final candidateSeconds = candidateAge / 1000;
      final candidateSpeed = candidateSeconds > 0
          ? candidateDistance / candidateSeconds
          : double.infinity;
      if (candidateAge > 0 &&
          candidateAge <= policy.continuityConfirmationWindowMillis &&
          candidateSpeed <= policy.maxSpeedMetersPerSecond) {
        _continuityConfirmations++;
        if (_continuityConfirmations >= policy.continuityConfirmationCount) {
          _baseline = point;
          _continuityCandidate = null;
          _continuityConfirmations = 0;
          _accept();
          return const LocationDecision(
            type: LocationDecisionType.reentryBaseline,
          );
        }
      } else {
        _continuityCandidate = null;
        _continuityConfirmations = 0;
      }
      return _reject(LocationRejectReason.continuityUnconfirmed);
    }

    final segment = geodesicDistanceMeters(previous, point);
    if (!segment.isFinite || segment < 0) {
      return _reject(LocationRejectReason.invalidSegment, segment: segment);
    }
    final elapsedSeconds = elapsed / 1000;
    final speed = elapsedSeconds > 0
        ? segment / elapsedSeconds
        : double.infinity;
    if (!speed.isFinite || speed > policy.maxSpeedMetersPerSecond) {
      if (policy.continuityConfirmationCount > 0) {
        _continuityCandidate = point;
        _continuityConfirmations = 0;
      }
      return _reject(
        LocationRejectReason.implausibleSpeed,
        segment: segment,
        speed: speed,
      );
    }

    final accuracyThreshold = math.min(
      policy.maxJitterMeters,
      ((previous.accuracyMeters ?? 0) + accuracy) * policy.accuracyJitterFactor,
    );
    final movementThreshold = math.max(
      policy.minSegmentMeters,
      accuracyThreshold,
    );
    if (segment < movementThreshold) {
      return _reject(
        LocationRejectReason.jitter,
        segment: segment,
        threshold: movementThreshold,
        speed: speed,
      );
    }
    totalDistanceMeters += segment;
    _baseline = point;
    _accept();
    return LocationDecision(
      type: LocationDecisionType.accepted,
      segmentMeters: segment,
      movementThresholdMeters: movementThreshold,
      impliedSpeedMetersPerSecond: speed,
    );
  }

  LocationDecision _reject(
    LocationRejectReason reason, {
    double segment = 0,
    double threshold = 0,
    double speed = 0,
  }) {
    diagnostics = diagnostics.copyWith(
      rejectedPoints: diagnostics.rejectedPoints + 1,
      lastRejectReason: reason,
    );
    return LocationDecision(
      type: LocationDecisionType.rejected,
      reason: reason,
      segmentMeters: segment,
      movementThresholdMeters: threshold,
      impliedSpeedMetersPerSecond: speed,
    );
  }

  void _accept() {
    diagnostics = diagnostics.copyWith(
      acceptedPoints: diagnostics.acceptedPoints + 1,
      clearRejectReason: true,
    );
  }

  void _resetContinuity() {
    _baseline = null;
    _continuityCandidate = null;
    _continuityConfirmations = 0;
    _lastProcessedMonotonicMillis = -1;
  }
}

double geodesicDistanceMeters(RawLocationSample from, RawLocationSample to) {
  const earthRadiusMeters = 6371008.8;
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final deltaLat = (to.latitude - from.latitude) * math.pi / 180;
  final deltaLon = (to.longitude - from.longitude) * math.pi / 180;
  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

int? averagePaceSecondsPerKm(
  int activeDurationMillis,
  double distanceMeters, {
  TrackingPolicy policy = TrackingPolicy.current,
}) {
  if (!distanceMeters.isFinite ||
      distanceMeters < policy.minimumPaceDistanceMeters ||
      activeDurationMillis <= 0) {
    return null;
  }
  final pace = (activeDurationMillis / 1000) / (distanceMeters / 1000);
  return pace.isFinite && pace > 0 ? pace.round() : null;
}
