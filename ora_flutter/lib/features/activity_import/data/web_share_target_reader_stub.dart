import '../domain/activity_share_payload.dart';

Future<ActivitySharePayload?> readPlatformWebShareTargetPayload(
  Uri uri,
) async => null;

void startPlatformWebShareTargetListener(
  Future<void> Function(ActivitySharePayload payload) onPayload,
) {}

void stopPlatformWebShareTargetListener() {}
