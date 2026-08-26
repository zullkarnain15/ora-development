import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/platform/pwa_install_controller.dart';
import 'package:ora_flutter/core/platform/pwa_install_platform.dart';
import 'package:ora_flutter/core/platform/pwa_install_rules.dart';

class _FakePlatform implements PwaInstallPlatform {
  _FakePlatform(this.currentState);

  PwaInstallState currentState;
  void Function()? listener;
  int promptCalls = 0;

  @override
  PwaInstallState get state => currentState;

  @override
  Future<bool> promptInstall() async {
    promptCalls++;
    return true;
  }

  @override
  void start(void Function() onStateChanged) => listener = onStateChanged;

  @override
  void stop() => listener = null;
}

void main() {
  test('shows native install only for eligible Android Chrome', () {
    expect(
      resolvePwaInstallState(
        isWeb: true,
        isStandalone: false,
        promptReady: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 15) Chrome/140.0 Mobile',
      ),
      PwaInstallState.install,
    );
    expect(
      resolvePwaInstallState(
        isWeb: true,
        isStandalone: false,
        promptReady: false,
        userAgent: 'Mozilla/5.0 (Linux; Android 15) Chrome/140.0 Mobile',
      ),
      PwaInstallState.hidden,
    );
  });

  test('shows Chrome guidance for Android in-app browsers', () {
    expect(
      resolvePwaInstallState(
        isWeb: true,
        isStandalone: false,
        promptReady: false,
        userAgent: 'Mozilla/5.0 (Linux; Android 15; wv) Version/4.0 Chrome/140.0 Mobile',
      ),
      PwaInstallState.openInChrome,
    );
  });

  test('shows iOS instructions and hides all installed modes', () {
    expect(
      resolvePwaInstallState(
        isWeb: true,
        isStandalone: false,
        promptReady: false,
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)',
      ),
      PwaInstallState.iosInstructions,
    );
    expect(
      resolvePwaInstallState(
        isWeb: true,
        isStandalone: true,
        promptReady: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 15) Chrome/140.0 Mobile',
      ),
      PwaInstallState.hidden,
    );
  });

  test(
    'controller invokes the captured native prompt and reacts to install',
    () async {
      final platform = _FakePlatform(PwaInstallState.install);
      final controller = PwaInstallController(platform: platform);
      addTearDown(controller.dispose);

      expect(await controller.promptInstall(), isTrue);
      expect(platform.promptCalls, 1);

      platform.currentState = PwaInstallState.hidden;
      platform.listener!();
      expect(controller.state, PwaInstallState.hidden);
    },
  );
}
