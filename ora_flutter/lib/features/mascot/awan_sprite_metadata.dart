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

  static const fallbackAssetPath = 'assets/mascot/awan/navy_awan_static.webp';

  static const byState = <AwanMascotState, AwanSpriteMetadata>{
    AwanMascotState.idle: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_idle.webp',
      frames: 4,
      fps: 4,
    ),
    AwanMascotState.ready: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_ready.webp',
      frames: 4,
      fps: 5,
    ),
    AwanMascotState.gps: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_gps.webp',
      frames: 4,
      fps: 4,
    ),
    AwanMascotState.running: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_running.webp',
      frames: 8,
      fps: 10,
    ),
    AwanMascotState.rest: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_rest.webp',
      frames: 4,
      fps: 3,
    ),
    AwanMascotState.cheer: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_cheer_v2.webp',
      frames: 4,
      fps: 5,
    ),
    AwanMascotState.success: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_success.webp',
      frames: 6,
      fps: 7,
    ),
    AwanMascotState.special: AwanSpriteMetadata(
      assetPath: 'assets/mascot/awan/navy_awan_special.webp',
      frames: 6,
      fps: 7,
    ),
  };

  static AwanSpriteMetadata forState(AwanMascotState state) =>
      byState[state] ?? byState[AwanMascotState.idle]!;
}
