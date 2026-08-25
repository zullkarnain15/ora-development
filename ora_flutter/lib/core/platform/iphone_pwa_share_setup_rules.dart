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
