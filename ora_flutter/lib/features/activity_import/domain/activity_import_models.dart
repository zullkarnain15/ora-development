import 'activity_share_payload.dart';

enum ActivityImportPaceStatus { unavailable, verified, reviewRequired }

enum ActivityImportErrorCode {
  importTokenInvalid,
  importExpired,
  importAlreadyUsed,
  noSharedData,
  noActivityData,
  partialData,
  ocrFailed,
  ocrNotAvailable,
  invalidDistance,
  invalidDuration,
  startTimeRequired,
  possibleDuplicate,
  backendError,
  importCancelled,
}

class ActivityImportDraft {
  const ActivityImportDraft({
    required this.source,
    required this.payload,
    this.distanceMeters,
    this.durationSeconds,
    this.detectedPaceSecondsPerKm,
    this.sourceRef,
    this.sourceUrl,
    this.startDateTime,
    this.exactDuplicate = false,
    this.possibleDuplicate = false,
    this.possibleDuplicateConfirmed = false,
    this.ocrFallbackRequired = false,
  });

  final ActivityImportSource source;
  final ActivitySharePayload payload;
  final double? distanceMeters;
  final int? durationSeconds;
  final int? detectedPaceSecondsPerKm;
  final String? sourceRef;
  final String? sourceUrl;
  final DateTime? startDateTime;
  final bool exactDuplicate;
  final bool possibleDuplicate;
  final bool possibleDuplicateConfirmed;
  final bool ocrFallbackRequired;

  int? get startEpochSeconds {
    final start = startDateTime;
    return start == null ? null : start.millisecondsSinceEpoch ~/ 1000;
  }

  int? get calculatedPaceSecondsPerKm {
    final distance = distanceMeters;
    final duration = durationSeconds;
    if (distance == null ||
        distance <= 0 ||
        duration == null ||
        duration <= 0) {
      return null;
    }
    return (duration / (distance / 1000)).round();
  }

  ActivityImportPaceStatus get paceStatus {
    final detected = detectedPaceSecondsPerKm;
    final calculated = calculatedPaceSecondsPerKm;
    if (detected == null || calculated == null) {
      return ActivityImportPaceStatus.unavailable;
    }
    return (detected - calculated).abs() <= 15
        ? ActivityImportPaceStatus.verified
        : ActivityImportPaceStatus.reviewRequired;
  }

  bool get canSave => validationErrors.isEmpty;

  Set<ActivityImportErrorCode> get validationErrors => {
    if (distanceMeters == null || !distanceMeters!.isFinite)
      ActivityImportErrorCode.invalidDistance
    else if (distanceMeters! <= 0)
      ActivityImportErrorCode.invalidDistance,
    if (durationSeconds == null || durationSeconds! <= 0)
      ActivityImportErrorCode.invalidDuration,
    if (startDateTime == null) ActivityImportErrorCode.startTimeRequired,
    if (source == ActivityImportSource.strava &&
        (sourceRef == null || sourceRef!.trim().isEmpty))
      ActivityImportErrorCode.noActivityData,
    if (exactDuplicate) ActivityImportErrorCode.possibleDuplicate,
  };

  ActivityImportDraft copyWith({
    ActivityImportSource? source,
    ActivitySharePayload? payload,
    double? distanceMeters,
    bool clearDistance = false,
    int? durationSeconds,
    bool clearDuration = false,
    int? detectedPaceSecondsPerKm,
    String? sourceRef,
    String? sourceUrl,
    DateTime? startDateTime,
    bool clearStartDateTime = false,
    bool? exactDuplicate,
    bool? possibleDuplicate,
    bool? possibleDuplicateConfirmed,
    bool? ocrFallbackRequired,
  }) => ActivityImportDraft(
    source: source ?? this.source,
    payload: payload ?? this.payload,
    distanceMeters: clearDistance
        ? null
        : distanceMeters ?? this.distanceMeters,
    durationSeconds: clearDuration
        ? null
        : durationSeconds ?? this.durationSeconds,
    detectedPaceSecondsPerKm:
        detectedPaceSecondsPerKm ?? this.detectedPaceSecondsPerKm,
    sourceRef: sourceRef ?? this.sourceRef,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    startDateTime: clearStartDateTime
        ? null
        : startDateTime ?? this.startDateTime,
    exactDuplicate: exactDuplicate ?? this.exactDuplicate,
    possibleDuplicate: possibleDuplicate ?? this.possibleDuplicate,
    possibleDuplicateConfirmed:
        possibleDuplicateConfirmed ?? this.possibleDuplicateConfirmed,
    ocrFallbackRequired: ocrFallbackRequired ?? this.ocrFallbackRequired,
  );
}
