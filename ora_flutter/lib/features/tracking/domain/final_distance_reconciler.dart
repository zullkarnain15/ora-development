import 'dart:math' as math;

import 'location_engine.dart';
import 'tracking_models.dart';

class ReconciliationPolicy {
  const ReconciliationPolicy({
    this.minimumSpikeExcessMeters = 25,
    this.minimumSpikeDetourRatio = 2.5,
    this.maximumSpikeWindow = const Duration(seconds: 12),
    this.minimumPoorAccuracyMeters = 20,
    this.minimumStationaryPoints = 5,
    this.minimumStationaryPathMeters = 35,
    this.maximumStationaryDisplacementMeters = 8,
    this.maximumStationarySpreadMeters = 25,
    this.maximumStationaryWindow = const Duration(seconds: 90),
    this.maximumAdjustmentFraction = .10,
    this.maximumAbsoluteAdjustmentMeters = 200,
  });

  final double minimumSpikeExcessMeters;
  final double minimumSpikeDetourRatio;
  final Duration maximumSpikeWindow;
  final double minimumPoorAccuracyMeters;
  final int minimumStationaryPoints;
  final double minimumStationaryPathMeters;
  final double maximumStationaryDisplacementMeters;
  final double maximumStationarySpreadMeters;
  final Duration maximumStationaryWindow;
  final double maximumAdjustmentFraction;
  final double maximumAbsoluteAdjustmentMeters;
}

class ReconciliationResult {
  const ReconciliationResult({
    required this.integratedDistanceMeters,
    required this.finalDistanceMeters,
    required this.adjustmentMeters,
    required this.correctedSpikeCount,
    required this.reducedDriftClusterCount,
    required this.suspicious,
    required this.flags,
  });

  final double integratedDistanceMeters;
  final double finalDistanceMeters;
  final double adjustmentMeters;
  final int correctedSpikeCount;
  final int reducedDriftClusterCount;
  final bool suspicious;
  final List<String> flags;
}

class FinalDistanceReconciler {
  const FinalDistanceReconciler({this.policy = const ReconciliationPolicy()});

  final ReconciliationPolicy policy;

  ReconciliationResult reconcile(List<PersistedPointDecision> decisions) {
    final integrated = decisions
        .where((item) => item.decision.type == LocationDecisionType.accepted)
        .fold<double>(0, (sum, item) => sum + item.decision.segmentMeters);
    if (integrated <= 0 || !integrated.isFinite) {
      return ReconciliationResult(
        integratedDistanceMeters: math.max(0, integrated),
        finalDistanceMeters: math.max(0, integrated),
        adjustmentMeters: 0,
        correctedSpikeCount: 0,
        reducedDriftClusterCount: 0,
        suspicious: false,
        flags: const [],
      );
    }

    final segments = _routeSegments(decisions);
    var correction = 0.0;
    var spikes = 0;
    var driftClusters = 0;
    for (final segment in segments) {
      final spikeResult = _spikeCorrection(segment);
      correction += spikeResult.correction;
      spikes += spikeResult.count;
      final driftResult = _stationaryCorrection(segment);
      correction += driftResult.correction;
      driftClusters += driftResult.count;
    }

    correction = math.min(correction, integrated);
    final suspicious =
        correction > policy.maximumAbsoluteAdjustmentMeters ||
        correction / integrated > policy.maximumAdjustmentFraction;
    if (suspicious) {
      return ReconciliationResult(
        integratedDistanceMeters: integrated,
        finalDistanceMeters: integrated,
        adjustmentMeters: 0,
        correctedSpikeCount: 0,
        reducedDriftClusterCount: 0,
        suspicious: true,
        flags: const ['RECONCILIATION_SUSPICIOUS'],
      );
    }
    final finalDistance = math.max(0.0, integrated - correction);
    return ReconciliationResult(
      integratedDistanceMeters: integrated,
      finalDistanceMeters: finalDistance,
      adjustmentMeters: finalDistance - integrated,
      correctedSpikeCount: spikes,
      reducedDriftClusterCount: driftClusters,
      suspicious: false,
      flags: correction > 0 ? const ['HIGH_CONFIDENCE_CORRECTION'] : const [],
    );
  }

  List<List<PersistedPointDecision>> _routeSegments(
    List<PersistedPointDecision> decisions,
  ) {
    final sorted = decisions.toList()
      ..sort((a, b) => a.sample.sequence.compareTo(b.sample.sequence));
    final segments = <List<PersistedPointDecision>>[];
    List<PersistedPointDecision>? current;
    for (final item in sorted) {
      final type = item.decision.type;
      if (type == LocationDecisionType.baseline ||
          type == LocationDecisionType.reentryBaseline) {
        current = [item];
        segments.add(current);
      } else if (type == LocationDecisionType.accepted) {
        current ??= <PersistedPointDecision>[];
        if (!segments.contains(current)) segments.add(current);
        current.add(item);
      }
    }
    return segments.where((segment) => segment.length >= 2).toList();
  }

  _Correction _spikeCorrection(List<PersistedPointDecision> points) {
    var correction = 0.0;
    var count = 0;
    for (var index = 1; index < points.length - 1; index += 1) {
      final before = points[index - 1].sample;
      final spike = points[index].sample;
      final after = points[index + 1].sample;
      final elapsed =
          after.providerMonotonicMillis - before.providerMonotonicMillis;
      if (elapsed <= 0 || elapsed > policy.maximumSpikeWindow.inMilliseconds) {
        continue;
      }
      final beforeAccuracy = before.accuracyMeters ?? double.infinity;
      final spikeAccuracy = spike.accuracyMeters ?? double.infinity;
      final afterAccuracy = after.accuracyMeters ?? double.infinity;
      final neighborsAccuracy = math.max(beforeAccuracy, afterAccuracy);
      if (spikeAccuracy < policy.minimumPoorAccuracyMeters ||
          spikeAccuracy < neighborsAccuracy * 1.5) {
        continue;
      }
      final firstLeg = geodesicDistanceMeters(before, spike);
      final secondLeg = geodesicDistanceMeters(spike, after);
      final direct = geodesicDistanceMeters(before, after);
      final detour = firstLeg + secondLeg;
      final excess = detour - direct;
      if (excess >= policy.minimumSpikeExcessMeters &&
          detour / math.max(1, direct) >= policy.minimumSpikeDetourRatio) {
        correction += excess;
        count += 1;
        index += 1;
      }
    }
    return _Correction(correction, count);
  }

  _Correction _stationaryCorrection(List<PersistedPointDecision> points) {
    if (points.length < policy.minimumStationaryPoints) {
      return const _Correction(0, 0);
    }
    var correction = 0.0;
    var count = 0;
    var start = 0;
    while (start <= points.length - policy.minimumStationaryPoints) {
      var found = false;
      final lastCandidate = math.min(points.length - 1, start + 11);
      for (
        var end = start + policy.minimumStationaryPoints - 1;
        end <= lastCandidate;
        end += 1
      ) {
        final candidateCorrection = _stationaryCandidate(
          points.sublist(start, end + 1),
        );
        if (candidateCorrection > 0) {
          correction += candidateCorrection;
          count += 1;
          start = end + 1;
          found = true;
          break;
        }
      }
      if (!found) start += 1;
    }
    return _Correction(correction, count);
  }

  double _stationaryCandidate(List<PersistedPointDecision> points) {
    final duration =
        points.last.sample.providerMonotonicMillis -
        points.first.sample.providerMonotonicMillis;
    if (duration <= 0 ||
        duration > policy.maximumStationaryWindow.inMilliseconds) {
      return 0;
    }
    var path = 0.0;
    var accuracyTotal = 0.0;
    for (var index = 1; index < points.length; index += 1) {
      path += geodesicDistanceMeters(
        points[index - 1].sample,
        points[index].sample,
      );
    }
    for (final point in points) {
      accuracyTotal += point.sample.accuracyMeters ?? 0;
    }
    final net = geodesicDistanceMeters(points.first.sample, points.last.sample);
    final averageAccuracy = accuracyTotal / points.length;
    final spread = _maximumSpread(points);
    final highConfidenceStationary =
        path >= policy.minimumStationaryPathMeters &&
        net <= policy.maximumStationaryDisplacementMeters &&
        spread <= policy.maximumStationarySpreadMeters &&
        averageAccuracy >= policy.minimumPoorAccuracyMeters &&
        path / math.max(1, net) >= 4;
    return highConfidenceStationary ? path - net : 0;
  }

  double _maximumSpread(List<PersistedPointDecision> points) {
    var spread = 0.0;
    for (var first = 0; first < points.length; first += 1) {
      for (var second = first + 1; second < points.length; second += 1) {
        spread = math.max(
          spread,
          geodesicDistanceMeters(points[first].sample, points[second].sample),
        );
      }
    }
    return spread;
  }
}

class _Correction {
  const _Correction(this.correction, this.count);
  final double correction;
  final int count;
}
