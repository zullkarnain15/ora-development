import 'tracking_models.dart';

class FieldDiagnosticSummary {
  const FieldDiagnosticSummary({
    required this.source,
    required this.soakDurationMillis,
    required this.soakSampleCount,
    required this.gpsStatusChanges,
    required this.rawCallbacks,
    required this.validCoordinatePoints,
    required this.acceptedPoints,
    required this.rejectedPoints,
    required this.badAccuracyRejects,
    required this.staleRejects,
    required this.outOfOrderRejects,
    required this.duplicateRejects,
    required this.jitterRejects,
    required this.minimumSegmentRejects,
    required this.continuityRejects,
    required this.implausibleSpeedRejects,
    required this.averageAcceptedAccuracyMeters,
    required this.averageRejectedAccuracyMeters,
    required this.averageCallbackIntervalMillis,
    required this.longestCallbackGapMillis,
    required this.realtimeDistanceMeters,
    required this.finalDistanceMeters,
    required this.flags,
  });

  final String source;
  final int soakDurationMillis;
  final int soakSampleCount;
  final int gpsStatusChanges;
  final int rawCallbacks;
  final int validCoordinatePoints;
  final int acceptedPoints;
  final int rejectedPoints;
  final int badAccuracyRejects;
  final int staleRejects;
  final int outOfOrderRejects;
  final int duplicateRejects;
  final int jitterRejects;
  final int minimumSegmentRejects;
  final int continuityRejects;
  final int implausibleSpeedRejects;
  final double? averageAcceptedAccuracyMeters;
  final double? averageRejectedAccuracyMeters;
  final double? averageCallbackIntervalMillis;
  final int longestCallbackGapMillis;
  final double realtimeDistanceMeters;
  final double finalDistanceMeters;
  final List<String> flags;

  double get adjustmentMeters => finalDistanceMeters - realtimeDistanceMeters;
  int get otherRejects =>
      rejectedPoints -
      badAccuracyRejects -
      staleRejects -
      outOfOrderRejects -
      duplicateRejects -
      jitterRejects -
      minimumSegmentRejects -
      continuityRejects -
      implausibleSpeedRejects;

  factory FieldDiagnosticSummary.fromDecisions({
    required String source,
    required List<PersistedPointDecision> decisions,
    required int soakDurationMillis,
    required int soakSampleCount,
    required int gpsStatusChanges,
    required double finalDistanceMeters,
    List<String> flags = const [],
  }) {
    final sorted = decisions.toList()
      ..sort(
        (a, b) => a.sample.receivedMonotonicMillis.compareTo(
          b.sample.receivedMonotonicMillis,
        ),
      );
    var validCoordinates = 0;
    var accepted = 0;
    var rejected = 0;
    var badAccuracy = 0;
    var stale = 0;
    var outOfOrder = 0;
    var duplicate = 0;
    var jitter = 0;
    var minimumSegment = 0;
    var continuity = 0;
    var implausibleSpeed = 0;
    var acceptedAccuracy = 0.0;
    var acceptedAccuracyCount = 0;
    var rejectedAccuracy = 0.0;
    var rejectedAccuracyCount = 0;
    var intervalTotal = 0;
    var longestGap = 0;
    for (var index = 0; index < sorted.length; index += 1) {
      final item = sorted[index];
      final sample = item.sample;
      if (sample.latitude.isFinite &&
          sample.longitude.isFinite &&
          sample.latitude >= -90 &&
          sample.latitude <= 90 &&
          sample.longitude >= -180 &&
          sample.longitude <= 180) {
        validCoordinates += 1;
      }
      final isAccepted =
          item.decision.type == LocationDecisionType.baseline ||
          item.decision.type == LocationDecisionType.reentryBaseline ||
          item.decision.type == LocationDecisionType.accepted;
      if (isAccepted) {
        accepted += 1;
        final accuracy = sample.accuracyMeters;
        if (accuracy != null && accuracy.isFinite && accuracy > 0) {
          acceptedAccuracy += accuracy;
          acceptedAccuracyCount += 1;
        }
      } else if (item.decision.type == LocationDecisionType.rejected) {
        rejected += 1;
        final accuracy = sample.accuracyMeters;
        if (accuracy != null && accuracy.isFinite && accuracy > 0) {
          rejectedAccuracy += accuracy;
          rejectedAccuracyCount += 1;
        }
        switch (item.decision.reason) {
          case LocationRejectReason.missingAccuracy:
          case LocationRejectReason.poorAccuracy:
            badAccuracy += 1;
          case LocationRejectReason.staleLocation:
          case LocationRejectReason.futureTimestamp:
            stale += 1;
          case LocationRejectReason.outOfOrder:
            outOfOrder += 1;
          case LocationRejectReason.duplicateCoordinate:
            duplicate += 1;
          case LocationRejectReason.jitter:
            jitter += 1;
          case LocationRejectReason.minimumSegment:
            minimumSegment += 1;
          case LocationRejectReason.continuityUnconfirmed:
            continuity += 1;
          case LocationRejectReason.implausibleSpeed:
            implausibleSpeed += 1;
          default:
            break;
        }
      }
      if (index > 0) {
        final gap =
            sample.receivedMonotonicMillis -
            sorted[index - 1].sample.receivedMonotonicMillis;
        if (gap >= 0) {
          intervalTotal += gap;
          if (gap > longestGap) longestGap = gap;
        }
      }
    }
    final realtime = decisions
        .where((item) => item.decision.type == LocationDecisionType.accepted)
        .fold<double>(0, (sum, item) => sum + item.decision.segmentMeters);
    return FieldDiagnosticSummary(
      source: source,
      soakDurationMillis: soakDurationMillis,
      soakSampleCount: soakSampleCount,
      gpsStatusChanges: gpsStatusChanges,
      rawCallbacks: decisions.length,
      validCoordinatePoints: validCoordinates,
      acceptedPoints: accepted,
      rejectedPoints: rejected,
      badAccuracyRejects: badAccuracy,
      staleRejects: stale,
      outOfOrderRejects: outOfOrder,
      duplicateRejects: duplicate,
      jitterRejects: jitter,
      minimumSegmentRejects: minimumSegment,
      continuityRejects: continuity,
      implausibleSpeedRejects: implausibleSpeed,
      averageAcceptedAccuracyMeters: acceptedAccuracyCount == 0
          ? null
          : acceptedAccuracy / acceptedAccuracyCount,
      averageRejectedAccuracyMeters: rejectedAccuracyCount == 0
          ? null
          : rejectedAccuracy / rejectedAccuracyCount,
      averageCallbackIntervalMillis: sorted.length < 2
          ? null
          : intervalTotal / (sorted.length - 1),
      longestCallbackGapMillis: longestGap,
      realtimeDistanceMeters: realtime,
      finalDistanceMeters: finalDistanceMeters,
      flags: List.unmodifiable(flags),
    );
  }

  String formatForLog() =>
      'SOURCE: $source\n'
      'SOAK: ${(soakDurationMillis / 1000).toStringAsFixed(1)}s / '
      '$soakSampleCount samples\n'
      'RAW POINTS: $rawCallbacks\n'
      'ACCEPTED: $acceptedPoints\n'
      'REJECTED: $rejectedPoints\n'
      'BAD ACCURACY: $badAccuracyRejects\n'
      'JITTER: $jitterRejects\n'
      'MIN SEGMENT: $minimumSegmentRejects\n'
      'CONTINUITY: $continuityRejects\n'
      'STALE: $staleRejects\n'
      'OUT OF ORDER: $outOfOrderRejects\n'
      'DUPLICATE: $duplicateRejects\n'
      'IMPLAUSIBLE SPEED: $implausibleSpeedRejects\n'
      'OTHER: $otherRejects\n'
      'AVG ACCEPTED ACCURACY: '
      '${averageAcceptedAccuracyMeters?.toStringAsFixed(1) ?? '-'}m\n'
      'AVG REJECTED ACCURACY: '
      '${averageRejectedAccuracyMeters?.toStringAsFixed(1) ?? '-'}m\n'
      'AVG CALLBACK INTERVAL: '
      '${averageCallbackIntervalMillis?.toStringAsFixed(0) ?? '-'}ms\n'
      'MAX CALLBACK GAP: ${(longestCallbackGapMillis / 1000).toStringAsFixed(1)}s\n'
      'REALTIME DISTANCE: ${(realtimeDistanceMeters / 1000).toStringAsFixed(3)} km\n'
      'RECONCILED: ${(finalDistanceMeters / 1000).toStringAsFixed(3)} km\n'
      'ADJUSTMENT: ${(adjustmentMeters / 1000).toStringAsFixed(3)} km\n'
      'GPS STATUS CHANGES: $gpsStatusChanges\n'
      'FLAGS: ${flags.isEmpty ? '-' : flags.join(',')}';
}
