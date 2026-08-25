import '../domain/activity_share_payload.dart';
import 'activity_ocr_engine.dart';

ActivityOcrEngine createPlatformActivityOcrEngine() =>
    const _UnsupportedActivityOcrEngine();

class _UnsupportedActivityOcrEngine implements ActivityOcrEngine {
  const _UnsupportedActivityOcrEngine();

  @override
  Future<String> recognize(ActivityShareImage image) =>
      Future.error(UnsupportedError('Activity OCR is unavailable.'));
}
