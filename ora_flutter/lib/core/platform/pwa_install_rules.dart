import 'pwa_install_platform.dart';

PwaInstallState resolvePwaInstallState({
  required bool isWeb,
  required bool isStandalone,
  required bool promptReady,
  required String userAgent,
  String platform = '',
  int maxTouchPoints = 0,
}) {
  if (!isWeb || isStandalone) return PwaInstallState.hidden;
  final agent = userAgent.toLowerCase();
  final ios =
      agent.contains('iphone') ||
      agent.contains('ipad') ||
      agent.contains('ipod') ||
      (platform == 'MacIntel' && maxTouchPoints > 1);
  if (ios) return PwaInstallState.iosInstructions;
  if (!agent.contains('android')) return PwaInstallState.hidden;
  if (!_isAndroidChrome(agent)) return PwaInstallState.openInChrome;
  return promptReady ? PwaInstallState.install : PwaInstallState.hidden;
}

bool _isAndroidChrome(String agent) {
  if (!agent.contains('chrome/')) return false;
  return ![
    '; wv)',
    ' version/4.0 chrome/',
    'edga/',
    'opr/',
    'opera',
    'samsungbrowser/',
    'firefox/',
    'fbav/',
    'fban/',
    'instagram',
    'line/',
  ].any(agent.contains);
}
