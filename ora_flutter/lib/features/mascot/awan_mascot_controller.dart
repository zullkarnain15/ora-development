import 'package:flutter/foundation.dart';

import '../tracking/domain/tracking_models.dart';
import 'awan_mascot_state.dart';

class AwanMascotController extends ChangeNotifier {
  AwanMascotController({AwanMascotState initialState = AwanMascotState.idle})
    : _state = initialState;

  AwanMascotState _state;
  AwanMascotState get state => _state;

  void show(AwanMascotState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  static AwanMascotState fromTracking(
    TrackingStatus status, {
    required bool gpsIsAccurate,
  }) => switch (status) {
    TrackingStatus.idle || TrackingStatus.gpsReady => AwanMascotState.ready,
    TrackingStatus.preparingGps ||
    TrackingStatus.acquiringGps ||
    TrackingStatus.reacquiring => AwanMascotState.gps,
    TrackingStatus.running => AwanMascotState.running,
    TrackingStatus.paused ||
    TrackingStatus.recoverableSession => AwanMascotState.rest,
    TrackingStatus.finished => AwanMascotState.success,
    TrackingStatus.error => AwanMascotState.idle,
    _ => gpsIsAccurate ? AwanMascotState.idle : AwanMascotState.gps,
  };

  void showTracking(TrackingStatus status, {required bool gpsIsAccurate}) =>
      show(fromTracking(status, gpsIsAccurate: gpsIsAccurate));
}
