import 'dart:convert';

import 'final_activity.dart';

enum SyncQueueState { pending, uploading, retry, acknowledged, notEligible }

extension SyncQueueStateValue on SyncQueueState {
  String get value => switch (this) {
    SyncQueueState.pending => 'PENDING',
    SyncQueueState.uploading => 'UPLOADING',
    SyncQueueState.retry => 'RETRY',
    SyncQueueState.acknowledged => 'ACKNOWLEDGED',
    SyncQueueState.notEligible => 'NOT_ELIGIBLE',
  };

  static SyncQueueState parse(String? value) => switch (value) {
    'UPLOADING' => SyncQueueState.uploading,
    'RETRY' => SyncQueueState.retry,
    'ACKNOWLEDGED' || 'SYNCED' => SyncQueueState.acknowledged,
    'NOT_ELIGIBLE' => SyncQueueState.notEligible,
    _ => SyncQueueState.pending,
  };
}

class ActivityUploadPayload {
  const ActivityUploadPayload({required this.version, required this.fields});

  final int version;
  final Map<String, Object?> fields;

  String encode() => jsonEncode(fields);

  factory ActivityUploadPayload.decode(int version, String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map) throw const FormatException('Invalid sync payload.');
    return ActivityUploadPayload(
      version: version,
      fields: value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

String? syncPayloadIneligibilityReason(ActivityUploadPayload payload) {
  final duration = payload.fields['durationSec'];
  if (duration is! num || !duration.isFinite || duration <= 0) {
    return 'NO_ACTIVE_DURATION';
  }
  final distance = payload.fields['distanceKm'];
  if (distance is! num || !distance.isFinite || distance <= 0) {
    return 'NO_GPS_DISTANCE';
  }
  return null;
}

abstract final class ActivityPayloadMapper {
  static const currentVersion = 2;

  static ActivityUploadPayload mapV2(
    FinalActivity activity, {
    required DateTime deviceTime,
  }) => ActivityUploadPayload(
    version: currentVersion,
    fields: {
      ...activity.toBackendJson(deviceTime: deviceTime),
      'source': activity.source == 'ANDROID'
          ? inferredActivitySource(activity.activityId)
          : activity.source,
    },
  );
}

String activitySourceFromId(String activityId) {
  return inferredActivitySource(activityId);
}

class SyncQueueEntry {
  const SyncQueueEntry({
    required this.queueId,
    required this.activityId,
    required this.ownerNik,
    required this.state,
    required this.retryCount,
    required this.payload,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    required this.nextAttemptAtMillis,
    this.lastAttemptAtMillis,
    this.serverStatus,
    this.serverAckAtMillis,
    this.lastErrorCode,
  });

  final String queueId;
  final String activityId;
  final String ownerNik;
  final SyncQueueState state;
  final int retryCount;
  final ActivityUploadPayload payload;
  final int createdAtMillis;
  final int updatedAtMillis;
  final int nextAttemptAtMillis;
  final int? lastAttemptAtMillis;
  final String? serverStatus;
  final int? serverAckAtMillis;
  final String? lastErrorCode;
}

class ActivityRoutePoint {
  const ActivityRoutePoint({
    required this.latitude,
    required this.longitude,
    required this.sequence,
  });

  final double latitude;
  final double longitude;
  final int sequence;
}

int syncBackoffMillis(int retryCount) {
  if (retryCount <= 0) return 0;
  final shift = (retryCount - 1).clamp(0, 7);
  return (30000 * (1 << shift)).clamp(30000, 3600000).toInt();
}
