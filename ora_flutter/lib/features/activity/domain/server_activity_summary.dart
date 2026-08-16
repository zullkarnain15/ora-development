import 'final_activity.dart';

class ServerActivitySummary {
  const ServerActivitySummary({
    required this.activityId,
    required this.startTime,
    required this.endTime,
    required this.durationSec,
    required this.distanceKm,
    required this.averagePaceSecondsPerKm,
    required this.status,
    required this.source,
    required this.syncedAt,
  });

  final String activityId;
  final DateTime startTime;
  final DateTime endTime;
  final double durationSec;
  final double distanceKm;
  final int? averagePaceSecondsPerKm;
  final String status;
  final String source;
  final DateTime? syncedAt;

  factory ServerActivitySummary.fromJson(Map<String, Object?> json) {
    final activityId = _requiredString(json, 'activityId');
    final startTime = DateTime.parse(_requiredString(json, 'startTime'));
    final endTime = DateTime.parse(_requiredString(json, 'endTime'));
    final durationSec = _requiredNumber(json, 'durationSec');
    final distanceKm = _requiredNumber(json, 'distanceKm');
    if (durationSec < 0 || distanceKm < 0) {
      throw const FormatException(
        'Activity summary values cannot be negative.',
      );
    }
    final syncedAtText = _optionalString(json['syncedAt']);
    return ServerActivitySummary(
      activityId: activityId,
      startTime: startTime,
      endTime: endTime,
      durationSec: durationSec,
      distanceKm: distanceKm,
      averagePaceSecondsPerKm: _parsePace(json['avgPace']),
      status: _optionalString(json['status']) ?? 'COMPLETED',
      source: _optionalString(json['source']) ?? '',
      syncedAt: syncedAtText == null ? null : DateTime.parse(syncedAtText),
    );
  }

  FinalActivity toFinalActivity(String ownerNik) => FinalActivity(
    activityId: activityId,
    ownerNik: ownerNik,
    nicknameSnapshot: null,
    divisionGuildSnapshot: null,
    startDateTimeMillis: startTime.millisecondsSinceEpoch,
    endDateTimeMillis: endTime.millisecondsSinceEpoch,
    distanceMeters: distanceKm * 1000,
    activeDurationMillis: (durationSec * 1000).round(),
    averagePaceSecondsPerKm: averagePaceSecondsPerKm,
    createdAtMillis:
        syncedAt?.millisecondsSinceEpoch ?? endTime.millisecondsSinceEpoch,
    syncStatus: ActivitySyncStatus.synced,
  );
}

List<FinalActivity> mergeActivityHistory({
  required String ownerNik,
  required List<FinalActivity> local,
  required List<ServerActivitySummary> backend,
}) {
  final merged = <String, FinalActivity>{
    for (final item in backend) item.activityId: item.toFinalActivity(ownerNik),
  };
  for (final item in local.where((item) => item.ownerNik == ownerNik)) {
    merged[item.activityId] = merged.containsKey(item.activityId)
        ? item.withSyncStatus(ActivitySyncStatus.synced)
        : item;
  }
  final result = merged.values.toList(growable: false);
  result.sort((a, b) {
    final byTime = _activityTimeMillis(b).compareTo(_activityTimeMillis(a));
    if (byTime != 0) return byTime;
    final byCreated = b.createdAtMillis.compareTo(a.createdAtMillis);
    return byCreated != 0 ? byCreated : b.activityId.compareTo(a.activityId);
  });
  return result;
}

int _activityTimeMillis(FinalActivity activity) =>
    activity.endDateTimeMillis > 0
    ? activity.endDateTimeMillis
    : activity.startDateTimeMillis;

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw FormatException('Missing activity field: $key');
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _requiredNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite) {
    throw FormatException('Invalid activity field: $key');
  }
  return number;
}

int? _parsePace(Object? value) {
  if (value is num && value.isFinite && value > 0) return value.round();
  final text = _optionalString(value);
  if (text == null) return null;
  final match = RegExp(r'^(\d+):([0-5]\d)').firstMatch(text);
  if (match == null) return null;
  final seconds = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  return seconds > 0 ? seconds : null;
}
