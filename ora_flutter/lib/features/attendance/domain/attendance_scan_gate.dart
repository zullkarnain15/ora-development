import 'package:flutter/foundation.dart';

/// Web camera access is provided by the browser over HTTPS. Native and web
/// builds intentionally share the same QR check-in flow.
bool supportsAttendanceQrCamera({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    isWeb ||
    platform == TargetPlatform.android ||
    platform == TargetPlatform.iOS;

/// Accepts exactly one QR value until the scanner is explicitly reset.
///
/// Camera decoders can emit the same frame more than once, so this gate keeps
/// a check-in request single-shot before it reaches the backend.
class AttendanceScanGate {
  String? _acceptedValue;

  bool accept(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || _acceptedValue != null) return false;
    _acceptedValue = normalized;
    return true;
  }

  void reset() => _acceptedValue = null;
}
