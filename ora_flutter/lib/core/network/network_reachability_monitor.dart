import 'dart:async';

import 'reachability_probe_io.dart'
    if (dart.library.js_interop) 'reachability_probe_web.dart';

typedef ReachabilityProbe = Future<bool> Function();

class NetworkReachabilityMonitor {
  NetworkReachabilityMonitor({
    required this.onRestored,
    ReachabilityProbe? probe,
    this.interval = const Duration(seconds: 20),
  }) : _probe = probe ?? defaultReachabilityProbe;

  final FutureOr<void> Function() onRestored;
  final Duration interval;
  final ReachabilityProbe _probe;
  Timer? _timer;
  bool? _wasReachable;
  bool _checking = false;

  void start() {
    if (_timer != null) return;
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _wasReachable = null;
  }

  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      var reachable = false;
      try {
        reachable = await _probe();
      } on Object {
        reachable = false;
      }
      final restored = _wasReachable == false && reachable;
      _wasReachable = reachable;
      if (restored) await onRestored();
    } finally {
      _checking = false;
    }
  }
}
