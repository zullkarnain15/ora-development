import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'pwa_install_platform.dart';
import 'pwa_install_rules.dart';

@JS('oraIsPwaStandalone')
external JSBoolean _isPwaStandalone();

@JS('oraCanPromptPwaInstall')
external JSBoolean _canPromptPwaInstall();

@JS('oraPromptPwaInstall')
external JSPromise<JSString> _promptPwaInstall();

PwaInstallPlatform createPlatformPwaInstallPlatform() =>
    _WebPwaInstallPlatform();

class _WebPwaInstallPlatform implements PwaInstallPlatform {
  JSFunction? _stateHandler;

  @override
  PwaInstallState get state => resolvePwaInstallState(
    isWeb: true,
    isStandalone: _isPwaStandalone().toDart,
    promptReady: _canPromptPwaInstall().toDart,
    userAgent: web.window.navigator.userAgent,
    platform: web.window.navigator.platform,
    maxTouchPoints: web.window.navigator.maxTouchPoints,
  );

  @override
  Future<bool> promptInstall() async {
    final result = await _promptPwaInstall().toDart;
    return result.toDart == 'accepted';
  }

  @override
  void start(void Function() onStateChanged) {
    stop();
    _stateHandler = ((web.Event _) => onStateChanged()).toJS;
    web.window.addEventListener('ora-pwa-install-state-changed', _stateHandler);
  }

  @override
  void stop() {
    final handler = _stateHandler;
    if (handler == null) return;
    web.window.removeEventListener('ora-pwa-install-state-changed', handler);
    _stateHandler = null;
  }
}
