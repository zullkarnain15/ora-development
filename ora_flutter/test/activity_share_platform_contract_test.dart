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

  test('PWA exposes a base-path-safe text URL and image share target', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final shareTarget = manifest['share_target'] as Map<String, Object?>;
    final params = shareTarget['params'] as Map<String, Object?>;
    final files = params['files'] as List<Object?>;
    final imageTarget = files.single as Map<String, Object?>;

    expect(manifest['short_name'], 'ORA');
    expect(
      (manifest['launch_handler'] as Map<String, Object?>)['client_mode'],
      'navigate-existing',
    );
    expect(shareTarget['action'], './share-target');
    expect(shareTarget['method'], 'POST');
    expect(shareTarget['enctype'], 'multipart/form-data');
    expect(params.keys, containsAll(['title', 'text', 'url']));
    expect(imageTarget['name'], 'activity_images');
    expect(imageTarget['accept'], contains('image/*'));

    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final worker = File('web/ora_service_worker.js').readAsStringSync();
    final ocr = File('web/ora_ocr.js').readAsStringSync();
    final install = File('web/ora_pwa_install.js').readAsStringSync();
    final index = File('web/index.html').readAsStringSync();
    expect(bootstrap, contains('serviceWorkerUrl: `ora_service_worker.js'));
    expect(worker, contains("request.formData()"));
    expect(worker, contains("form.getAll('activity_images')"));
    expect(worker, contains("type: 'ORA_ACTIVITY_SHARE'"));
    expect(worker, contains('client.postMessage(message)'));
    expect(worker, contains("Response.redirect(destination.toString(), 303)"));
    expect(ocr, contains('oraActualImageMimeType'));
    expect(ocr, contains("canvas.toDataURL('image/png')"));
    expect(ocr, contains("name: 'lower-stats-contrast'"));
    expect(index, contains('src="ora_pwa_install.js"'));
    expect(install, contains("window.addEventListener('beforeinstallprompt'"));
    expect(install, contains("window.addEventListener('appinstalled'"));
    expect(install, contains('await prompt.prompt()'));
  });
}
