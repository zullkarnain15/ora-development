import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ora_flutter/features/mascot/awan_mascot.dart';
import 'package:ora_flutter/features/mascot/awan_sprite_metadata.dart';

void main() {
  testWidgets('sprite sheet keeps its full width inside the clipped viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: AwanMascot(size: 80))),
    );

    final image = tester.renderObject<RenderBox>(find.byType(Image));
    expect(image.size, const Size(320, 80));
  });

  testWidgets('every mascot sprite uses square, distortion-free frames', (
    tester,
  ) async {
    final checkedAssets = <String>{};
    for (final metadata in AwanSpriteMetadata.byState.values) {
      if (!checkedAssets.add(metadata.assetPath)) continue;

      final bytes = await rootBundle.load(metadata.assetPath);
      final imageWidth = bytes.getUint32(16);
      final imageHeight = bytes.getUint32(20);

      expect(
        imageWidth,
        imageHeight * metadata.frames,
        reason: '${metadata.assetPath} must contain square frame cells',
      );
    }
  });
}
