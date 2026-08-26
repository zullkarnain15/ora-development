import 'pwa_install_platform_stub.dart'
    if (dart.library.js_interop) 'pwa_install_platform_web.dart';

enum PwaInstallState { hidden, install, openInChrome, iosInstructions }

abstract interface class PwaInstallPlatform {
  PwaInstallState get state;

  void start(void Function() onStateChanged);

  void stop();

  Future<bool> promptInstall();
}

PwaInstallPlatform createPwaInstallPlatform() =>
    createPlatformPwaInstallPlatform();
