import 'package:web/web.dart' as web;

import '../network/apps_script_client.dart';
import 'iphone_pwa_share_setup_rules.dart';

bool get isIphonePwaShareSetupAvailable => isIphonePwaBrowser(
  isWeb: true,
  userAgent: web.window.navigator.userAgent,
  platform: web.window.navigator.platform,
  maxTouchPoints: web.window.navigator.maxTouchPoints,
);

Future<void> openIphonePwaShareShortcut() async {
  final data = await AppsScriptClient().get('iphoneShortcut');
  final uri = requireIcloudShortcutUri(data['linkIcloud']);
  web.window.location.assign(uri.toString());
}
