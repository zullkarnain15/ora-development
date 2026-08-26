import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_share_payload.dart';

void main() {
  test('normalizes a PNG from byte signature instead of JPEG metadata', () {
    final image = ActivityShareImage(
      bytes: Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      mimeType: 'image/jpeg',
      name: 'activity.jpg',
    ).normalized();

    expect(image.mimeType, 'image/png');
    expect(image.name, 'activity.png');
  });

  test('normalizes JPEG bytes even when the filename says PNG', () {
    final image = ActivityShareImage(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
      mimeType: 'image/png',
      name: 'activity.png',
    ).normalized();

    expect(image.mimeType, 'image/jpeg');
    expect(image.name, 'activity.jpg');
  });
}
