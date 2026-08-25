import 'package:web/web.dart' as web;

import 'iphone_pwa_share_setup_rules.dart';

const iphoneShareShortcutUrl =
    'https://www.icloud.com/shortcuts/30c3fe6ba4ef4381ba5e75019c150768';

bool get isIphonePwaShareSetupAvailable => isIphonePwaBrowser(
  isWeb: true,
  userAgent: web.window.navigator.userAgent,
  platform: web.window.navigator.platform,
  maxTouchPoints: web.window.navigator.maxTouchPoints,
);

Future<void> openIphonePwaShareShortcut() async {
  final link = web.HTMLAnchorElement()
    ..href = iphoneShareShortcutUrl
    ..target = '_blank'
    ..rel = 'noopener noreferrer';
  link.click();
}
