import 'dart:js_interop';

import '../domain/activity_share_payload.dart';
import 'activity_ocr_engine.dart';

@JS('oraRecognizeActivityImage')
external JSPromise<JSString> _recognizeActivityImage(
  JSUint8Array bytes,
  String mimeType,
);

ActivityOcrEngine createPlatformActivityOcrEngine() =>
    const _WebActivityOcrEngine();

class _WebActivityOcrEngine implements ActivityOcrEngine {
  const _WebActivityOcrEngine();

  @override
  Future<String> recognize(ActivityShareImage image) async {
    final result = await _recognizeActivityImage(
      image.bytes.toJS,
      image.mimeType,
    ).toDart;
    return result.toDart.trim();
  }
}
