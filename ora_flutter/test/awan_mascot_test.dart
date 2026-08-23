import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ora_flutter/features/mascot/awan_mascot.dart';

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
}
