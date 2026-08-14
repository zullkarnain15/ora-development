import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/network_reachability_monitor.dart';

void main() {
  test('fires only when reachability changes from offline to online', () async {
    var reachable = false;
    var restored = 0;
    final monitor = NetworkReachabilityMonitor(
      probe: () async => reachable,
      onRestored: () => restored++,
      interval: const Duration(days: 1),
    );
    await monitor.checkNow();
    expect(restored, 0);
    reachable = true;
    await monitor.checkNow();
    expect(restored, 1);
    await monitor.checkNow();
    expect(restored, 1);
    monitor.stop();
  });
}
