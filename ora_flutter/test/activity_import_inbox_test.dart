import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity_import/application/activity_import_inbox.dart';
import 'package:ora_flutter/features/activity_import/data/activity_import_launch_store.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_share_payload.dart';

class _SharedLaunchStore implements ActivityImportLaunchStore {
  Map<String, Object?>? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<Map<String, Object?>?> load() async => value;

  @override
  Future<void> save(Map<String, Object?> value) async {
    this.value = Map<String, Object?>.from(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads token from the GitHub Pages hash import route', () {
    final launch = ActivityImportLaunch.fromUri(
      Uri.parse('https://example.com/ora/#/import?t=opaque-token'),
    );

    expect(launch?.token, 'opaque-token');
    expect(launch?.hasRequest, isTrue);
  });

  test('reads token from the backend-generated query import URL', () {
    final launch = ActivityImportLaunch.fromUri(
      Uri.parse(
        'https://zullkarnain15.github.io/ora-development/?t=opaque-token',
      ),
    );

    expect(launch?.token, 'opaque-token');
    expect(launch?.hasRequest, isTrue);
  });

  test('bare internal import route cannot open a manual import flow', () {
    expect(
      ActivityImportLaunch.fromUri(
        Uri.parse('https://example.com/ora/#/import'),
      ),
      isNull,
    );
    expect(
      ActivityImportLaunch.fromUri(
        Uri.parse('https://example.com/ora/?share_target=1'),
      ),
      isNull,
    );
  });

  test('reads Android PWA GET share target text and URL', () {
    final launch = ActivityImportLaunch.fromUri(
      Uri.parse(
        'https://example.com/ora/?share_target=1&title=Morning%20Run&text=5%20km&url=https%3A%2F%2Fstrava.com%2Fa%2F1',
      ),
    );

    expect(launch?.payload?.sharedText, 'Morning Run\n5 km');
    expect(launch?.payload?.sharedUrl, 'https://strava.com/a/1');
  });

  test('PWA share failure opens a visible Strava preview error', () {
    final launch = ActivityImportLaunch.fromUri(
      Uri.parse(
        'https://example.com/ora/?share_target=1&share_error=read_failed',
      ),
    );

    expect(launch?.hasRequest, isTrue);
    expect(launch?.payload?.sourceHint, 'STRAVA');
    expect(launch?.payload?.sharedText, 'STRAVA SHARE COULD NOT BE READ');
  });

  test(
    'pending import survives recreation for login and reload resume',
    () async {
      final store = _SharedLaunchStore();
      final first = ActivityImportInbox(store: store);
      await first.receive(
        ActivityImportLaunch(
          token: 'resume-after-login',
          payload: ActivitySharePayload(
            sharedText: 'Morning Run',
            receivedAt: DateTime(2026, 8, 25),
          ),
        ),
      );
      first.dispose();

      final resumed = ActivityImportInbox(store: store);
      await resumed.initialize();

      expect(resumed.current?.token, 'resume-after-login');
      expect(resumed.current?.payload?.sharedText, 'Morning Run');
      await resumed.clear();
      expect(store.value, isNull);
      resumed.dispose();
    },
  );
}
