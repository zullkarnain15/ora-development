enum AwanMascotState {
  idle,
  ready,
  gps,
  running,
  rest,
  cheer,
  success,
  special,
}

extension AwanMascotStateValue on AwanMascotState {
  bool get playsOnce =>
      this == AwanMascotState.success || this == AwanMascotState.special;
}
