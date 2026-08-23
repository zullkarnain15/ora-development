import 'dart:js_interop';

import 'package:web/web.dart' as web;

extension type _MediaStreamLike(JSObject _) implements JSObject {
  external JSArray<web.MediaStreamTrack> getTracks();
}

/// Releases video tracks retained by web scanner backends after they stop
/// decoding. This is deliberately limited to video elements with a MediaStream.
void releaseAttendanceBrowserCamera() {
  _releaseCameraVideos(web.document.querySelectorAll('video'));

  // Flutter renders HtmlElementView inside this Shadow DOM on modern web
  // renderers, so document.querySelectorAll alone cannot reach the preview.
  final flutterHost = web.document.querySelector('flt-glass-pane');
  final flutterRoot = flutterHost?.shadowRoot;
  if (flutterRoot != null) {
    _releaseCameraVideos(flutterRoot.querySelectorAll('video'));
  }
}

void _releaseCameraVideos(web.NodeList videos) {
  for (var index = 0; index < videos.length; index += 1) {
    final node = videos.item(index);
    if (node == null) continue;
    final video = node as web.HTMLVideoElement;
    final source = video.srcObject;
    if (source != null) {
      try {
        final stream = _MediaStreamLike(source);
        for (final track in stream.getTracks().toDart) {
          track.stop();
        }
      } on Object {
        // Ignore non-camera video sources.
      }
    }
    video.pause();
    video.srcObject = null;
  }
}
