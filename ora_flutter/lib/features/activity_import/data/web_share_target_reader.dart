import '../domain/activity_share_payload.dart';
import 'web_share_target_reader_stub.dart'
    if (dart.library.js_interop) 'web_share_target_reader_web.dart';

Future<ActivitySharePayload?> readWebShareTargetPayload(Uri uri) =>
    readPlatformWebShareTargetPayload(uri);

void startWebShareTargetListener(
  Future<void> Function(ActivitySharePayload payload) onPayload,
) => startPlatformWebShareTargetListener(onPayload);

void stopWebShareTargetListener() => stopPlatformWebShareTargetListener();
