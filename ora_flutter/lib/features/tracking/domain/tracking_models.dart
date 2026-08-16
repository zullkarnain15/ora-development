enum TrackingStatus {
  idle,
  preparingGps,
  gpsReady,
  startRequested,
  acquiringGps,
  running,
  paused,
  reacquiring,
  finalizing,
  finished,
  recoverableSession,
  error,
}

extension TrackingStatusValue on TrackingStatus {
  String get value => switch (this) {
    TrackingStatus.idle => 'IDLE',
    TrackingStatus.preparingGps => 'PREPARING_GPS',
    TrackingStatus.gpsReady => 'GPS_READY',
    TrackingStatus.startRequested => 'START_REQUESTED',
    TrackingStatus.acquiringGps => 'ACQUIRING_GPS',
    TrackingStatus.running => 'RUNNING',
    TrackingStatus.paused => 'PAUSED',
    TrackingStatus.reacquiring => 'REACQUIRING',
    TrackingStatus.finalizing => 'FINALIZING',
    TrackingStatus.finished => 'FINISHED',
    TrackingStatus.recoverableSession => 'RECOVERABLE_SESSION',
    TrackingStatus.error => 'ERROR',
  };

  static TrackingStatus parse(String? value) => switch (value) {
    'PREPARING_GPS' => TrackingStatus.preparingGps,
    'GPS_READY' => TrackingStatus.gpsReady,
    'START_REQUESTED' => TrackingStatus.startRequested,
    'ACQUIRING_GPS' => TrackingStatus.acquiringGps,
    'RUNNING' => TrackingStatus.running,
    'PAUSED' => TrackingStatus.paused,
    'REACQUIRING' => TrackingStatus.reacquiring,
    'FINALIZING' => TrackingStatus.finalizing,
    'FINISHED' => TrackingStatus.finished,
    'RECOVERABLE_SESSION' => TrackingStatus.recoverableSession,
    'ERROR' => TrackingStatus.error,
    _ => TrackingStatus.idle,
  };
}

enum GpsQuality { unknown, excellent, good, weak, poor }

enum LocationDecisionType {
  baseline,
  reentryBaseline,
  accepted,
  rejected,
  ignored,
}

extension LocationDecisionTypeValue on LocationDecisionType {
  String get value => switch (this) {
    LocationDecisionType.baseline => 'BASELINE',
    LocationDecisionType.reentryBaseline => 'REENTRY_BASELINE',
    LocationDecisionType.accepted => 'ACCEPTED',
    LocationDecisionType.rejected => 'REJECTED',
    LocationDecisionType.ignored => 'IGNORED',
  };

  static LocationDecisionType parse(String? value) => switch (value) {
    'BASELINE' => LocationDecisionType.baseline,
    'REENTRY_BASELINE' => LocationDecisionType.reentryBaseline,
    'ACCEPTED' => LocationDecisionType.accepted,
    'REJECTED' => LocationDecisionType.rejected,
    _ => LocationDecisionType.ignored,
  };
}

enum LocationRejectReason {
  notTracking,
  invalidCoordinates,
  futureTimestamp,
  staleLocation,
  outOfOrder,
  missingAccuracy,
  poorAccuracy,
  duplicateCoordinate,
  invalidSegment,
  minimumSegment,
  jitter,
  implausibleSpeed,
  continuityUnconfirmed,
}

extension LocationRejectReasonValue on LocationRejectReason {
  String get value => switch (this) {
    LocationRejectReason.notTracking => 'NOT_TRACKING',
    LocationRejectReason.invalidCoordinates => 'INVALID_COORDINATES',
    LocationRejectReason.futureTimestamp => 'FUTURE_TIMESTAMP',
    LocationRejectReason.staleLocation => 'STALE_LOCATION',
    LocationRejectReason.outOfOrder => 'OUT_OF_ORDER',
    LocationRejectReason.missingAccuracy => 'MISSING_ACCURACY',
    LocationRejectReason.poorAccuracy => 'POOR_ACCURACY',
    LocationRejectReason.duplicateCoordinate => 'DUPLICATE_COORDINATE',
    LocationRejectReason.invalidSegment => 'INVALID_SEGMENT',
    LocationRejectReason.minimumSegment => 'MINIMUM_SEGMENT',
    LocationRejectReason.jitter => 'JITTER',
    LocationRejectReason.implausibleSpeed => 'IMPLAUSIBLE_SPEED',
    LocationRejectReason.continuityUnconfirmed => 'CONTINUITY_UNCONFIRMED',
  };

  static LocationRejectReason? parse(String? value) => switch (value) {
    'NOT_TRACKING' => LocationRejectReason.notTracking,
    'INVALID_COORDINATES' => LocationRejectReason.invalidCoordinates,
    'FUTURE_TIMESTAMP' => LocationRejectReason.futureTimestamp,
    'STALE_LOCATION' => LocationRejectReason.staleLocation,
    'OUT_OF_ORDER' => LocationRejectReason.outOfOrder,
    'MISSING_ACCURACY' => LocationRejectReason.missingAccuracy,
    'POOR_ACCURACY' => LocationRejectReason.poorAccuracy,
    'DUPLICATE_COORDINATE' => LocationRejectReason.duplicateCoordinate,
    'INVALID_SEGMENT' => LocationRejectReason.invalidSegment,
    'MINIMUM_SEGMENT' => LocationRejectReason.minimumSegment,
    'JITTER' => LocationRejectReason.jitter,
    'IMPLAUSIBLE_SPEED' => LocationRejectReason.implausibleSpeed,
    'CONTINUITY_UNCONFIRMED' => LocationRejectReason.continuityUnconfirmed,
    _ => null,
  };

  String get message => switch (this) {
    LocationRejectReason.notTracking => 'tracking is paused or inactive',
    LocationRejectReason.invalidCoordinates => 'invalid coordinates',
    LocationRejectReason.futureTimestamp => 'timestamp is in the future',
    LocationRejectReason.staleLocation => 'stale location',
    LocationRejectReason.outOfOrder => 'duplicate or out-of-order timestamp',
    LocationRejectReason.missingAccuracy => 'missing accuracy',
    LocationRejectReason.poorAccuracy => 'poor accuracy',
    LocationRejectReason.duplicateCoordinate => 'duplicate coordinate',
    LocationRejectReason.invalidSegment => 'invalid segment distance',
    LocationRejectReason.minimumSegment => 'movement below minimum segment',
    LocationRejectReason.jitter => 'movement below jitter threshold',
    LocationRejectReason.implausibleSpeed => 'implausible running speed',
    LocationRejectReason.continuityUnconfirmed =>
      'location continuity is not confirmed',
  };
}

class TrackingPolicy {
  const TrackingPolicy({
    required this.version,
    this.maxAccuracyMeters = 30,
    this.minSegmentMeters = 2,
    this.maxJitterMeters = 5,
    this.accuracyJitterFactor = .25,
    this.maxSpeedMetersPerSecond = 12,
    this.maxLocationAgeMillis = 15000,
    this.reentryGapMillis = 10000,
    this.minimumPaceDistanceMeters = 20,
    this.continuityConfirmationCount = 1,
    this.continuityConfirmationWindowMillis = 8000,
  });

  final int version;
  final double maxAccuracyMeters;
  final double minSegmentMeters;
  final double maxJitterMeters;
  final double accuracyJitterFactor;
  final double maxSpeedMetersPerSecond;
  final int maxLocationAgeMillis;
  final int reentryGapMillis;
  final double minimumPaceDistanceMeters;
  final int continuityConfirmationCount;
  final int continuityConfirmationWindowMillis;

  /// Exact threshold parity with the previous Android RunLocationEngine.
  static const androidParityV1 = TrackingPolicy(
    version: 1,
    continuityConfirmationCount: 0,
  );

  /// Sprint 3 adds jump continuity confirmation without weakening any threshold.
  static const current = TrackingPolicy(version: 2);
}

class RawLocationSample {
  const RawLocationSample({
    required this.latitude,
    required this.longitude,
    required this.providerMonotonicMillis,
    required this.receivedMonotonicMillis,
    required this.epochMillis,
    required this.sequence,
    this.accuracyMeters,
    this.provider = 'unknown',
    this.isMocked = false,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final int providerMonotonicMillis;
  final int receivedMonotonicMillis;
  final int epochMillis;
  final int sequence;
  final String provider;
  final bool isMocked;

  GpsQuality quality(TrackingPolicy policy) {
    final accuracy = accuracyMeters;
    if (accuracy == null || !accuracy.isFinite || accuracy <= 0) {
      return GpsQuality.unknown;
    }
    if (accuracy <= 10) return GpsQuality.excellent;
    if (accuracy <= 20) return GpsQuality.good;
    if (accuracy <= policy.maxAccuracyMeters) return GpsQuality.weak;
    return GpsQuality.poor;
  }

  factory RawLocationSample.fromNative(
    Map<Object?, Object?> map,
  ) => RawLocationSample(
    latitude: (map['latitude']! as num).toDouble(),
    longitude: (map['longitude']! as num).toDouble(),
    accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
    providerMonotonicMillis: (map['providerMonotonicMillis']! as num).toInt(),
    receivedMonotonicMillis: (map['receivedMonotonicMillis']! as num).toInt(),
    epochMillis: (map['epochMillis']! as num).toInt(),
    sequence: (map['sequence']! as num).toInt(),
    provider: map['provider'] as String? ?? 'unknown',
    isMocked: map['isMocked'] as bool? ?? false,
  );
}

class LocationDecision {
  const LocationDecision({
    required this.type,
    this.reason,
    this.segmentMeters = 0,
    this.movementThresholdMeters = 0,
    this.impliedSpeedMetersPerSecond = 0,
  });
  final LocationDecisionType type;
  final LocationRejectReason? reason;
  final double segmentMeters;
  final double movementThresholdMeters;
  final double impliedSpeedMetersPerSecond;
}

class TrackingDiagnostics {
  const TrackingDiagnostics({
    this.latestAccuracyMeters,
    this.acceptedPoints = 0,
    this.rejectedPoints = 0,
    this.lastRejectReason,
    this.firstRawCallbackLatencyMillis,
  });
  final double? latestAccuracyMeters;
  final int acceptedPoints;
  final int rejectedPoints;
  final LocationRejectReason? lastRejectReason;
  final int? firstRawCallbackLatencyMillis;

  TrackingDiagnostics copyWith({
    double? latestAccuracyMeters,
    int? acceptedPoints,
    int? rejectedPoints,
    LocationRejectReason? lastRejectReason,
    bool clearRejectReason = false,
    int? firstRawCallbackLatencyMillis,
  }) => TrackingDiagnostics(
    latestAccuracyMeters: latestAccuracyMeters ?? this.latestAccuracyMeters,
    acceptedPoints: acceptedPoints ?? this.acceptedPoints,
    rejectedPoints: rejectedPoints ?? this.rejectedPoints,
    lastRejectReason: clearRejectReason
        ? null
        : (lastRejectReason ?? this.lastRejectReason),
    firstRawCallbackLatencyMillis:
        firstRawCallbackLatencyMillis ?? this.firstRawCallbackLatencyMillis,
  );
}

class RunSession {
  const RunSession({
    required this.sessionId,
    required this.ownerNik,
    required this.nicknameSnapshot,
    required this.divisionGuildSnapshot,
    required this.status,
    required this.policyVersion,
    required this.startEpochMillis,
    required this.startMonotonicMillis,
    required this.bootEpochMillis,
    required this.activeAccumulatedMillis,
    required this.lastCheckpointMonotonicMillis,
    required this.distanceMeters,
    required this.acceptedPoints,
    required this.rejectedPoints,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.endEpochMillis,
    this.activeAnchorMonotonicMillis,
    this.lastRejectReason,
    this.finalActivityId,
  });

  final String sessionId;
  final String ownerNik;
  final String? nicknameSnapshot;
  final String? divisionGuildSnapshot;
  final TrackingStatus status;
  final int policyVersion;
  final int startEpochMillis;
  final int? endEpochMillis;
  final int startMonotonicMillis;
  final int bootEpochMillis;
  final int activeAccumulatedMillis;
  final int? activeAnchorMonotonicMillis;
  final int lastCheckpointMonotonicMillis;
  final double distanceMeters;
  final int acceptedPoints;
  final int rejectedPoints;
  final String? lastRejectReason;
  final String? finalActivityId;
  final int createdAtMillis;
  final int updatedAtMillis;

  RunSession copyWith({
    TrackingStatus? status,
    int? endEpochMillis,
    bool clearEndEpoch = false,
    int? activeAccumulatedMillis,
    int? activeAnchorMonotonicMillis,
    bool clearActiveAnchor = false,
    int? lastCheckpointMonotonicMillis,
    double? distanceMeters,
    int? acceptedPoints,
    int? rejectedPoints,
    String? lastRejectReason,
    bool clearRejectReason = false,
    String? finalActivityId,
    int? updatedAtMillis,
  }) => RunSession(
    sessionId: sessionId,
    ownerNik: ownerNik,
    nicknameSnapshot: nicknameSnapshot,
    divisionGuildSnapshot: divisionGuildSnapshot,
    status: status ?? this.status,
    policyVersion: policyVersion,
    startEpochMillis: startEpochMillis,
    endEpochMillis: clearEndEpoch
        ? null
        : (endEpochMillis ?? this.endEpochMillis),
    startMonotonicMillis: startMonotonicMillis,
    bootEpochMillis: bootEpochMillis,
    activeAccumulatedMillis:
        activeAccumulatedMillis ?? this.activeAccumulatedMillis,
    activeAnchorMonotonicMillis: clearActiveAnchor
        ? null
        : (activeAnchorMonotonicMillis ?? this.activeAnchorMonotonicMillis),
    lastCheckpointMonotonicMillis:
        lastCheckpointMonotonicMillis ?? this.lastCheckpointMonotonicMillis,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    acceptedPoints: acceptedPoints ?? this.acceptedPoints,
    rejectedPoints: rejectedPoints ?? this.rejectedPoints,
    lastRejectReason: clearRejectReason
        ? null
        : (lastRejectReason ?? this.lastRejectReason),
    finalActivityId: finalActivityId ?? this.finalActivityId,
    createdAtMillis: createdAtMillis,
    updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
  );

  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'ownerNik': ownerNik,
    'nicknameSnapshot': nicknameSnapshot,
    'divisionGuildSnapshot': divisionGuildSnapshot,
    'status': status.value,
    'policyVersion': policyVersion,
    'startEpochMillis': startEpochMillis,
    'endEpochMillis': endEpochMillis,
    'startMonotonicMillis': startMonotonicMillis,
    'bootEpochMillis': bootEpochMillis,
    'activeAccumulatedMillis': activeAccumulatedMillis,
    'activeAnchorMonotonicMillis': activeAnchorMonotonicMillis,
    'lastCheckpointMonotonicMillis': lastCheckpointMonotonicMillis,
    'distanceMeters': distanceMeters,
    'acceptedPoints': acceptedPoints,
    'rejectedPoints': rejectedPoints,
    'lastRejectReason': lastRejectReason,
    'finalActivityId': finalActivityId,
    'createdAtMillis': createdAtMillis,
    'updatedAtMillis': updatedAtMillis,
  };

  factory RunSession.fromMap(Map<String, Object?> map) => RunSession(
    sessionId: map['sessionId']! as String,
    ownerNik: map['ownerNik']! as String,
    nicknameSnapshot: map['nicknameSnapshot'] as String?,
    divisionGuildSnapshot: map['divisionGuildSnapshot'] as String?,
    status: TrackingStatusValue.parse(map['status'] as String?),
    policyVersion: (map['policyVersion']! as num).toInt(),
    startEpochMillis: (map['startEpochMillis']! as num).toInt(),
    endEpochMillis: (map['endEpochMillis'] as num?)?.toInt(),
    startMonotonicMillis: (map['startMonotonicMillis']! as num).toInt(),
    bootEpochMillis: (map['bootEpochMillis']! as num).toInt(),
    activeAccumulatedMillis: (map['activeAccumulatedMillis']! as num).toInt(),
    activeAnchorMonotonicMillis: (map['activeAnchorMonotonicMillis'] as num?)
        ?.toInt(),
    lastCheckpointMonotonicMillis:
        (map['lastCheckpointMonotonicMillis']! as num).toInt(),
    distanceMeters: (map['distanceMeters']! as num).toDouble(),
    acceptedPoints: (map['acceptedPoints']! as num).toInt(),
    rejectedPoints: (map['rejectedPoints']! as num).toInt(),
    lastRejectReason: map['lastRejectReason'] as String?,
    finalActivityId: map['finalActivityId'] as String?,
    createdAtMillis: (map['createdAtMillis']! as num).toInt(),
    updatedAtMillis: (map['updatedAtMillis']! as num).toInt(),
  );
}

class RunEvent {
  const RunEvent({
    required this.eventId,
    required this.sessionId,
    required this.type,
    required this.monotonicMillis,
    required this.epochMillis,
    this.fromStatus,
    this.toStatus,
    this.details,
  });
  final String eventId;
  final String sessionId;
  final String type;
  final TrackingStatus? fromStatus;
  final TrackingStatus? toStatus;
  final int monotonicMillis;
  final int epochMillis;
  final String? details;

  Map<String, Object?> toMap() => {
    'eventId': eventId,
    'sessionId': sessionId,
    'type': type,
    'fromStatus': fromStatus?.value,
    'toStatus': toStatus?.value,
    'monotonicMillis': monotonicMillis,
    'epochMillis': epochMillis,
    'details': details,
  };
}

class PersistedPointDecision {
  const PersistedPointDecision({
    required this.sessionId,
    required this.sample,
    required this.decision,
  });
  final String sessionId;
  final RawLocationSample sample;
  final LocationDecision decision;

  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'sequence': sample.sequence,
    'latitude': sample.latitude,
    'longitude': sample.longitude,
    'accuracyMeters': sample.accuracyMeters,
    'provider': sample.provider,
    'providerMonotonicMillis': sample.providerMonotonicMillis,
    'receivedMonotonicMillis': sample.receivedMonotonicMillis,
    'epochMillis': sample.epochMillis,
    'isMocked': sample.isMocked ? 1 : 0,
    'decision': decision.type.value,
    'rejectReason': decision.reason?.value,
    'segmentMeters': decision.type == LocationDecisionType.accepted
        ? decision.segmentMeters
        : 0,
  };

  factory PersistedPointDecision.fromMap(Map<String, Object?> map) {
    final decisionType = LocationDecisionTypeValue.parse(
      map['decision'] as String?,
    );
    return PersistedPointDecision(
      sessionId: map['sessionId']! as String,
      sample: RawLocationSample(
        latitude: (map['latitude']! as num).toDouble(),
        longitude: (map['longitude']! as num).toDouble(),
        accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
        provider: map['provider'] as String? ?? 'unknown',
        providerMonotonicMillis: (map['providerMonotonicMillis']! as num)
            .toInt(),
        receivedMonotonicMillis: (map['receivedMonotonicMillis']! as num)
            .toInt(),
        epochMillis: (map['epochMillis']! as num).toInt(),
        sequence: (map['sequence']! as num).toInt(),
        isMocked: ((map['isMocked'] as num?)?.toInt() ?? 0) == 1,
      ),
      decision: LocationDecision(
        type: decisionType,
        reason: LocationRejectReasonValue.parse(map['rejectReason'] as String?),
        segmentMeters: decisionType == LocationDecisionType.accepted
            ? ((map['segmentMeters'] as num?)?.toDouble() ?? 0)
            : 0,
      ),
    );
  }
}

class NativeClockSnapshot {
  const NativeClockSnapshot({
    required this.monotonicMillis,
    required this.epochMillis,
    required this.bootEpochMillis,
  });
  final int monotonicMillis;
  final int epochMillis;
  final int bootEpochMillis;

  factory NativeClockSnapshot.fromMap(Map<Object?, Object?> map) =>
      NativeClockSnapshot(
        monotonicMillis: (map['monotonicMillis']! as num).toInt(),
        epochMillis: (map['epochMillis']! as num).toInt(),
        bootEpochMillis: (map['bootEpochMillis']! as num).toInt(),
      );
}

enum LocationPermissionState {
  notDetermined,
  denied,
  approximate,
  precise,
  restricted,
}

class NativeTrackingStatus {
  const NativeTrackingStatus({
    required this.permission,
    required this.locationEnabled,
    required this.serviceActive,
    required this.notificationGranted,
    this.sessionId,
    this.trackingState,
    this.lastActiveMonotonicMillis,
    this.pendingAction,
    this.errorCode,
  });
  final LocationPermissionState permission;
  final bool locationEnabled;
  final bool serviceActive;
  final bool notificationGranted;
  final String? sessionId;
  final String? trackingState;
  final int? lastActiveMonotonicMillis;
  final String? pendingAction;
  final String? errorCode;

  factory NativeTrackingStatus.fromMap(Map<Object?, Object?> map) =>
      NativeTrackingStatus(
        permission: switch (map['permission']) {
          'precise' => LocationPermissionState.precise,
          'approximate' => LocationPermissionState.approximate,
          'denied' => LocationPermissionState.denied,
          'restricted' => LocationPermissionState.restricted,
          _ => LocationPermissionState.notDetermined,
        },
        locationEnabled: map['locationEnabled'] as bool? ?? false,
        serviceActive: map['serviceActive'] as bool? ?? false,
        notificationGranted: map['notificationGranted'] as bool? ?? true,
        sessionId: map['sessionId'] as String?,
        trackingState: map['trackingState'] as String?,
        lastActiveMonotonicMillis: (map['lastActiveMonotonicMillis'] as num?)
            ?.toInt(),
        pendingAction: map['pendingAction'] as String?,
        errorCode: map['errorCode'] as String?,
      );
}

class NativeTrackingEvent {
  const NativeTrackingEvent({
    required this.type,
    this.sample,
    this.code,
    this.message,
  });
  final String type;
  final RawLocationSample? sample;
  final String? code;
  final String? message;

  factory NativeTrackingEvent.fromMap(Map<Object?, Object?> map) =>
      NativeTrackingEvent(
        type: map['type'] as String? ?? 'unknown',
        sample: map['type'] == 'location'
            ? RawLocationSample.fromNative(map)
            : null,
        code: map['code'] as String?,
        message: map['message'] as String?,
      );
}
