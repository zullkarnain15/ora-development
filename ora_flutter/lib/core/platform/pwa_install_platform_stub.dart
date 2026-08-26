import 'pwa_install_platform.dart';

PwaInstallPlatform createPlatformPwaInstallPlatform() =>
    const _UnsupportedPwaInstallPlatform();

class _UnsupportedPwaInstallPlatform implements PwaInstallPlatform {
  const _UnsupportedPwaInstallPlatform();

  @override
  PwaInstallState get state => PwaInstallState.hidden;

  @override
  Future<bool> promptInstall() async => false;

  @override
  void start(void Function() onStateChanged) {}

  @override
  void stop() {}
}
