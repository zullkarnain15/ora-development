import '../domain/activity_share_payload.dart';
import 'activity_ocr_engine_stub.dart'
    if (dart.library.js_interop) 'activity_ocr_engine_web.dart';

abstract interface class ActivityOcrEngine {
  Future<String> recognize(ActivityShareImage image);
}

ActivityOcrEngine createActivityOcrEngine() =>
    createPlatformActivityOcrEngine();
