import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/domain/field_diagnostics.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

PersistedPointDecision _point(
  int sequence,
  LocationDecision decision, {
  double accuracy = 5,
  int? receivedMillis,
}) => PersistedPointDecision(
  sessionId: 'S1',
  sample: RawLocationSample(
    latitude: -6.2,
    longitude: 106.8 + sequence * .00001,
    accuracyMeters: accuracy,
    providerMonotonicMillis: sequence * 1000,
    receivedMonotonicMillis: receivedMillis ?? sequence * 1000,
    epochMillis: 100000 + sequence * 1000,
    sequence: sequence,
  ),
  decision: decision,
);

void main() {
  test('diagnostics expose rejection distribution without coordinates', () {
    final decisions = [
      _point(1, const LocationDecision(type: LocationDecisionType.baseline)),
      _point(
        2,
        const LocationDecision(
          type: LocationDecisionType.accepted,
          segmentMeters: 10,
        ),
      ),
      _point(
        3,
        const LocationDecision(
          type: LocationDecisionType.rejected,
          reason: LocationRejectReason.poorAccuracy,
        ),
        accuracy: 50,
      ),
      _point(
        4,
        const LocationDecision(
          type: LocationDecisionType.rejected,
          reason: LocationRejectReason.jitter,
        ),
      ),
      _point(
        5,
        const LocationDecision(
          type: LocationDecisionType.rejected,
          reason: LocationRejectReason.minimumSegment,
        ),
      ),
      _point(
        6,
        const LocationDecision(
          type: LocationDecisionType.rejected,
          reason: LocationRejectReason.continuityUnconfirmed,
        ),
      ),
    ];
    final summary = FieldDiagnosticSummary.fromDecisions(
      source: 'WEB',
      decisions: decisions,
      soakDurationMillis: 5000,
      soakSampleCount: 5,
      gpsStatusChanges: 3,
      finalDistanceMeters: 10,
    );
    expect(summary.rawCallbacks, 6);
    expect(summary.acceptedPoints, 2);
    expect(summary.rejectedPoints, 4);
    expect(summary.badAccuracyRejects, 1);
    expect(summary.jitterRejects, 1);
    expect(summary.minimumSegmentRejects, 1);
    expect(summary.continuityRejects, 1);
    expect(summary.formatForLog(), isNot(contains('-6.2')));
    expect(summary.formatForLog(), isNot(contains('106.8')));
  });

  test('callback interval average and longest gap are tracked', () {
    final summary = FieldDiagnosticSummary.fromDecisions(
      source: 'WEB',
      decisions: [
        _point(
          1,
          const LocationDecision(type: LocationDecisionType.baseline),
          receivedMillis: 1000,
        ),
        _point(
          2,
          const LocationDecision(
            type: LocationDecisionType.accepted,
            segmentMeters: 10,
          ),
          receivedMillis: 3000,
        ),
        _point(
          3,
          const LocationDecision(
            type: LocationDecisionType.accepted,
            segmentMeters: 10,
          ),
          receivedMillis: 9000,
        ),
      ],
      soakDurationMillis: 0,
      soakSampleCount: 0,
      gpsStatusChanges: 0,
      finalDistanceMeters: 20,
    );
    expect(summary.averageCallbackIntervalMillis, 4000);
    expect(summary.longestCallbackGapMillis, 6000);
  });
}
