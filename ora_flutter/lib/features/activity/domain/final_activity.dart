enum ActivitySyncStatus { localOnly, pending, synced, notEligible }

extension ActivitySyncStatusValue on ActivitySyncStatus {
  String get value => switch (this) {
    ActivitySyncStatus.localOnly => 'LOCAL_ONLY',
    ActivitySyncStatus.pending => 'PENDING',
    ActivitySyncStatus.synced => 'SYNCED',
    ActivitySyncStatus.notEligible => 'NOT_ELIGIBLE',
  };

  static ActivitySyncStatus parse(String value) => switch (value) {
    'LOCAL_ONLY' => ActivitySyncStatus.localOnly,
    'SYNCED' => ActivitySyncStatus.synced,
    'NOT_ELIGIBLE' => ActivitySyncStatus.notEligible,
    _ => ActivitySyncStatus.pending,
  };
}

String? activitySyncIneligibilityReason(FinalActivity activity) {
  if (activity.activeDurationMillis <= 0) return 'NO_ACTIVE_DURATION';
  if (!activity.distanceMeters.isFinite || activity.distanceMeters <= 0) {
    return 'NO_GPS_DISTANCE';
  }
  return null;
}

class FinalActivity {
  const FinalActivity({
    required this.activityId,
    required this.ownerNik,
    required this.nicknameSnapshot,
    required this.divisionGuildSnapshot,
    required this.startDateTimeMillis,
    required this.endDateTimeMillis,
    required this.distanceMeters,
    required this.activeDurationMillis,
    required this.averagePaceSecondsPerKm,
    required this.createdAtMillis,
    this.syncStatus = ActivitySyncStatus.pending,
  });

  final String activityId;
  final String ownerNik;
  final String? nicknameSnapshot;
  final String? divisionGuildSnapshot;
  final int startDateTimeMillis;
  final int endDateTimeMillis;
  final double distanceMeters;
  final int activeDurationMillis;
  final int? averagePaceSecondsPerKm;
  final int createdAtMillis;
  final ActivitySyncStatus syncStatus;

  FinalActivity withSyncStatus(ActivitySyncStatus value) => FinalActivity(
    activityId: activityId,
    ownerNik: ownerNik,
    nicknameSnapshot: nicknameSnapshot,
    divisionGuildSnapshot: divisionGuildSnapshot,
    startDateTimeMillis: startDateTimeMillis,
    endDateTimeMillis: endDateTimeMillis,
    distanceMeters: distanceMeters,
    activeDurationMillis: activeDurationMillis,
    averagePaceSecondsPerKm: averagePaceSecondsPerKm,
    createdAtMillis: createdAtMillis,
    syncStatus: value,
  );

  Map<String, Object?> toMap() => {
    'activityId': activityId,
    'ownerNik': ownerNik,
    'nicknameSnapshot': nicknameSnapshot,
    'divisionGuildSnapshot': divisionGuildSnapshot,
    'startDateTimeMillis': startDateTimeMillis,
    'endDateTimeMillis': endDateTimeMillis,
    'distanceMeters': distanceMeters.isFinite && distanceMeters >= 0
        ? distanceMeters
        : 0,
    'activeDurationMillis': activeDurationMillis < 0 ? 0 : activeDurationMillis,
    'averagePaceSecondsPerKm':
        averagePaceSecondsPerKm != null && averagePaceSecondsPerKm! > 0
        ? averagePaceSecondsPerKm
        : null,
    'createdAtMillis': createdAtMillis,
    'syncStatus': syncStatus.value,
  };

  Map<String, Object?> toBackendJson({DateTime? deviceTime}) => {
    'activityId': activityId,
    'startTime': isoOffsetFromMillis(startDateTimeMillis),
    'endTime': isoOffsetFromMillis(endDateTimeMillis),
    'durationSec': activeDurationMillis / 1000.0,
    'distanceKm': distanceMeters / 1000.0,
    'avgPace': paceText(averagePaceSecondsPerKm),
    'deviceTime': isoOffset(deviceTime ?? DateTime.now()),
  };

  factory FinalActivity.fromMap(Map<String, Object?> map) => FinalActivity(
    activityId: map['activityId']! as String,
    ownerNik: map['ownerNik']! as String,
    nicknameSnapshot: map['nicknameSnapshot'] as String?,
    divisionGuildSnapshot: map['divisionGuildSnapshot'] as String?,
    startDateTimeMillis: (map['startDateTimeMillis']! as num).toInt(),
    endDateTimeMillis: (map['endDateTimeMillis']! as num).toInt(),
    distanceMeters: (map['distanceMeters']! as num).toDouble(),
    activeDurationMillis: (map['activeDurationMillis']! as num).toInt(),
    averagePaceSecondsPerKm: (map['averagePaceSecondsPerKm'] as num?)?.toInt(),
    createdAtMillis: (map['createdAtMillis']! as num).toInt(),
    syncStatus: ActivitySyncStatusValue.parse(map['syncStatus']! as String),
  );
}

class ActivityTotals {
  const ActivityTotals({
    required this.activityCount,
    required this.totalDistanceMeters,
    required this.totalActiveDurationMillis,
  });
  final int activityCount;
  final double totalDistanceMeters;
  final int totalActiveDurationMillis;

  static const zero = ActivityTotals(
    activityCount: 0,
    totalDistanceMeters: 0,
    totalActiveDurationMillis: 0,
  );
}

String paceText(int? secondsPerKm) {
  if (secondsPerKm == null || secondsPerKm <= 0) return '';
  return '${(secondsPerKm ~/ 60).toString().padLeft(2, '0')}:${(secondsPerKm % 60).toString().padLeft(2, '0')}';
}

String isoOffsetFromMillis(int millis) =>
    isoOffset(DateTime.fromMillisecondsSinceEpoch(millis));

String isoOffset(DateTime value) {
  final local = value.toLocal();
  final base =
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}T${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}.'
      '${local.millisecond.toString().padLeft(3, '0')}';
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  return '$base$sign${absolute.inHours.toString().padLeft(2, '0')}:'
      '${(absolute.inMinutes % 60).toString().padLeft(2, '0')}';
}
