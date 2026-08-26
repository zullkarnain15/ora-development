import 'package:flutter/foundation.dart';

import 'pwa_install_platform.dart';

class PwaInstallController extends ChangeNotifier {
  PwaInstallController({PwaInstallPlatform? platform})
    : _platform = platform ?? createPwaInstallPlatform() {
    _state = _platform.state;
    _platform.start(_refresh);
  }

  final PwaInstallPlatform _platform;
  late PwaInstallState _state;

  PwaInstallState get state => _state;

  Future<bool> promptInstall() async {
    if (_state != PwaInstallState.install) return false;
    final accepted = await _platform.promptInstall();
    _refresh();
    return accepted;
  }

  void _refresh() {
    final next = _platform.state;
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _platform.stop();
    super.dispose();
  }
}
