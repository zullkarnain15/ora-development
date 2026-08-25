import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android exposes Send to ORA for text images and lifecycle delivery', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/otorunners/ora_flutter/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:label="Send to ORA"'));
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
    expect(manifest, contains('android:mimeType="text/plain"'));
    expect(manifest, contains('android:mimeType="image/*"'));
    expect(manifest, contains('android:launchMode="singleTop"'));

    expect(mainActivity, contains('getInitialSharePayload'));
    expect(
      mainActivity,
      contains('captureShareIntent(intent, notifyDart = false)'),
    );
    expect(mainActivity, contains('override fun onNewIntent(intent: Intent)'));
    expect(
      mainActivity,
      contains('captureShareIntent(intent, notifyDart = true)'),
    );
    expect(mainActivity, contains('onSharePayload'));
  });

  test('PWA exposes a base-path-safe text and URL share target', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final shareTarget = manifest['share_target'] as Map<String, Object?>;
    final params = shareTarget['params'] as Map<String, Object?>;

    expect(manifest['short_name'], 'ORA');
    expect(shareTarget['action'], './?share_target=1');
    expect(shareTarget['method'], 'GET');
    expect(params.keys, containsAll(['title', 'text', 'url']));
  });
}
