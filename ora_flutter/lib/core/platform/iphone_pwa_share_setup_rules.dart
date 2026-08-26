bool isIphonePwaBrowser({
  required bool isWeb,
  required String userAgent,
  String platform = '',
  int maxTouchPoints = 0,
}) {
  if (!isWeb) return false;
  final normalizedAgent = userAgent.toLowerCase();
  if (normalizedAgent.contains('iphone') ||
      normalizedAgent.contains('ipod') ||
      normalizedAgent.contains('ipad')) {
    return true;
  }
  // iPadOS desktop mode identifies as Mac, but retains touch points.
  return platform == 'MacIntel' && maxTouchPoints > 1;
}

Uri requireIcloudShortcutUri(Object? value) {
  final uri = Uri.tryParse(value is String ? value.trim() : '');
  final valid =
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'www.icloud.com' &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first.toLowerCase() == 'shortcuts' &&
      RegExp(r'^[a-zA-Z0-9]+$').hasMatch(uri.pathSegments.last);
  if (!valid) {
    throw const FormatException('Invalid iCloud Shortcut URL.');
  }
  return uri;
}
