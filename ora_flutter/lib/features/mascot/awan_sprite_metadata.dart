import 'awan_mascot_state.dart';

class AwanSpriteMetadata {
  const AwanSpriteMetadata({
    required this.assetPath,
    required this.frames,
    required this.fps,
  });

  final String assetPath;
  final int frames;
  final double fps;

  static const fallbackAssetPath = 'assets/mascot/awan/navy_awan_static.png';

  static const byState = <AwanMascotState, AwanSpriteMetadata>{
    AwanMascotState.idle: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_ready.png',
      frames: 4,
      fps: 5,
    ),
    AwanMascotState.ready: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_ready.png',
      frames: 4,
      fps: 5,
    ),
    AwanMascotState.gps: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_gps.png',
      frames: 6,
      fps: 5,
    ),
    AwanMascotState.running: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_running.png',
      frames: 8,
      fps: 10,
    ),
    AwanMascotState.rest: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_rest.png',
      frames: 8,
      fps: 3,
    ),
    AwanMascotState.cheer: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_success.png',
      frames: 5,
      fps: 5,
    ),
    AwanMascotState.success: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_success.png',
      frames: 5,
      fps: 6,
    ),
    AwanMascotState.special: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_special.png',
      frames: 6,
      fps: 7,
    ),
  };

  static AwanSpriteMetadata forState(AwanMascotState state) =>
      byState[state] ?? byState[AwanMascotState.idle]!;
}
