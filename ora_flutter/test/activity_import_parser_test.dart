import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_import_models.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_import_parser.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_share_payload.dart';

void main() {
  const parser = ActivityImportParser();

  ActivitySharePayload payload(String text, {String? url}) =>
      ActivitySharePayload(
        sharedText: text,
        sharedUrl: url,
        receivedAt: DateTime(2026, 8, 25),
      );

  test('parses common Strava distance duration and pace text', () {
    final result = parser.parse(
      payload('Morning Run\n8.09 km\n58:06\n7:10/km'),
    );

    expect(result.distanceMeters, 8090);
    expect(result.durationSeconds, 3486);
    expect(result.detectedPaceSecondsPerKm, 430);
    expect(result.paceStatus, ActivityImportPaceStatus.verified);
    expect(result.startDateTime, isNull);
    expect(result.canSave, isFalse);
  });

  test('parses all supported Strava image template OCR outputs', () {
    const templates = <String, String>{
      'club summary': '''
OTO RUNNERS
Distance     Pace       Time
5.04 km      7:41 /km   38m 47s
STRAVA
''',
      'share card': '''
Distance 5.04 km   Pace 7:41 /km   Time 38m 47s
Evening Run
Check out my activity on STRAVA
''',
      'portrait map': '''
Evening Run
Pace
7:41 /km
Time
38m 47s
Distance
5.04 km
''',
    };

    for (final entry in templates.entries) {
      final result = parser.parse(payload(entry.value));
      expect(result.distanceMeters, 5040, reason: entry.key);
      expect(result.durationSeconds, 2327, reason: entry.key);
      expect(result.detectedPaceSecondsPerKm, 461, reason: entry.key);
    }
  });

  test('parses the black Strava share card Time value next to its label', () {
    final result = parser.parse(
      payload('''
STRAVA
Distance        Pace          Time
4.26 km         6:27 /km      27m 31s
'''),
    );

    expect(result.source, ActivityImportSource.strava);
    expect(result.distanceMeters, 4260);
    expect(result.detectedPaceSecondsPerKm, 387);
    expect(result.durationSeconds, 1651);
    expect(result.derivedFromPace, isFalse);
  });

  test(
    'derives a Strava duration from valid distance and pace when Time fails',
    () {
      final result = parser.parse(
        payload('STRAVA\nDistance 4.26 km\nPace 6:27 /km'),
      );

      expect(result.distanceMeters, 4260);
      expect(result.detectedPaceSecondsPerKm, 387);
      expect(result.durationSeconds, 1649);
      expect(result.derivedFromPace, isTrue);
    },
  );

  test('profiles an unbranded Distance Pace Time card as Strava', () {
    final result = parser.parse(
      payload('Distance 4.26 km\nPace 6:27 /km\nTime 27m 31s'),
    );

    expect(result.source, ActivityImportSource.strava);
    expect(result.durationSeconds, 1651);
  });

  test('normalizes a common Strava Time OCR error in the seconds value', () {
    final result = parser.parse(
      payload('STRAVA\nDistance 4.26 km\nPace 6:27 /km\nTime 27m 3ls'),
    );

    expect(result.durationSeconds, 1651);
    expect(result.derivedFromPace, isFalse);
  });

  test(
    'does not invent duration from distance and pace when Time is missing',
    () {
      final result = parser.parse(payload('Distance 5.04 km\nPace 7:41 /km'));

      expect(result.distanceMeters, 5040);
      expect(result.detectedPaceSecondsPerKm, 461);
      expect(result.durationSeconds, isNull);
      expect(result.calculatedPaceSecondsPerKm, isNull);
    },
  );

  test('keeps an explicitly labelled whole-minute Strava duration', () {
    final result = parser.parse(
      payload('Distance\n3.03 km\nTime\n25m\nPace\n8:21 /km'),
    );

    expect(result.distanceMeters, 3030);
    expect(result.detectedPaceSecondsPerKm, 501);
    expect(result.durationSeconds, 1500);
    expect(result.calculatedPaceSecondsPerKm, 495);
  });

  test('maps Garmin Total Time without requiring a Garmin logo', () {
    final result = parser.parse(
      payload(
        'Morning Run\nDistance 10.00 km\nTotal Time 1:02:03\nAvg Pace 6:12 /km',
      ),
    );

    expect(result.source, ActivityImportSource.garmin);
    expect(result.distanceMeters, 10000);
    expect(result.durationSeconds, 3723);
    expect(result.calculatedPaceSecondsPerKm, 372);
  });

  test('maps Huawei Duration and ignores calories on a photo card', () {
    final result = parser.parse(
      payload(
        'HUAWEI HEALTH\nCalories 463 kcal\nDistance 5.02 km\n'
        'Duration 00:42:16\nAverage Pace 8\'25"',
      ),
    );

    expect(result.source, ActivityImportSource.huawei);
    expect(result.distanceMeters, 5020);
    expect(result.durationSeconds, 2536);
    expect(result.detectedPaceSecondsPerKm, 505);
    expect(result.calculatedPaceSecondsPerKm, 505);
  });

  test('never interprets a Huawei calorie value as a metric', () {
    final result = parser.parse(
      payload('HUAWEI HEALTH\nCalories 463 kcal\nAverage Heart Rate 151 bpm'),
    );

    expect(result.distanceMeters, isNull);
    expect(result.durationSeconds, isNull);
  });

  test('maps Strava Moving Time and tolerates ikm pace OCR', () {
    final result = parser.parse(
      payload('STRAVA\nDistance 1.00 km\nMoving Time 17:11\nPace 17\'11" ikm'),
    );

    expect(result.distanceMeters, 1000);
    expect(result.durationSeconds, 1031);
    expect(result.detectedPaceSecondsPerKm, 1031);
    expect(result.calculatedPaceSecondsPerKm, 1031);
  });

  test('distance and duration are sufficient and pace is recalculated', () {
    final result = parser.parse(payload('Distance 5 km\nDuration 30:00'));

    expect(result.distanceMeters, 5000);
    expect(result.durationSeconds, 1800);
    expect(result.detectedPaceSecondsPerKm, isNull);
    expect(result.calculatedPaceSecondsPerKm, 360);
  });

  test('detects source and parses duration written with units', () {
    final result = parser.parse(
      payload(
        'Strava Morning Run\n5.00 km\n58m 6s',
        url: 'https://www.strava.com/activities/123',
      ),
    );

    expect(result.source, ActivityImportSource.strava);
    expect(result.durationSeconds, 3486);
    expect(result.payload.sharedUrl, contains('strava.com'));
    expect(result.sourceRef, '123');
    expect(result.sourceUrl, 'https://www.strava.com/activities/123');
  });

  test('extracts SourceRef from a Strava app short link', () {
    final result = parser.parse(
      payload(
        'Strava Morning Run\n5 km\n30:00',
        url: 'https://strava.app.link/Full6cF8S5b',
      ),
    );

    expect(result.sourceRef, 'Full6cF8S5b');
    expect(result.sourceUrl, 'https://strava.app.link/Full6cF8S5b');
  });

  test('canonical activity URL takes priority over a Strava short link', () {
    final result = parser.parse(
      payload(
        'Strava Morning Run\n5 km\n30:00\nhttps://www.strava.com/activities/987654',
        url: 'https://strava.app.link/ShortCode',
      ),
    );

    expect(result.sourceRef, '987654');
    expect(result.sourceUrl, 'https://www.strava.com/activities/987654');
  });

  test('URL-only share never invents activity metrics', () {
    final result = parser.parse(
      payload('', url: 'https://www.strava.com/activities/123'),
    );

    expect(result.source, ActivityImportSource.strava);
    expect(result.distanceMeters, isNull);
    expect(result.durationSeconds, isNull);
    expect(result.startDateTime, isNull);
  });

  test('requires an explicit date and explicitly labelled start time', () {
    final complete = parser.parse(
      payload('5 km\n30:00\n25 Aug 2026\nStarted at 06:15'),
    );
    final dateOnly = parser.parse(payload('5 km\n30:00\n25 Aug 2026'));

    expect(complete.startDateTime, DateTime(2026, 8, 25, 6, 15));
    expect(
      complete.startEpochSeconds,
      DateTime(2026, 8, 25, 6, 15).millisecondsSinceEpoch ~/ 1000,
    );
    expect(complete.canSave, isTrue);
    expect(dateOnly.startDateTime, isNull);
    expect(
      dateOnly.validationErrors,
      contains(ActivityImportErrorCode.startTimeRequired),
    );
  });

  test('flags a pace mismatch beyond the fifteen second tolerance', () {
    final result = parser.parse(
      payload('5 km\n30:00\n8:00/km\n2026-08-25 at 06:15'),
    );

    expect(result.calculatedPaceSecondsPerKm, 360);
    expect(result.paceStatus, ActivityImportPaceStatus.reviewRequired);
  });

  test('shared text source takes priority over a conflicting shared URL', () {
    final result = parser.parse(
      payload(
        'Garmin activity\n5 km\n30:00',
        url: 'https://www.strava.com/activities/123',
      ),
    );

    expect(result.source, ActivityImportSource.garmin);
  });

  test('image OCR fallback is requested only when text is incomplete', () {
    final image = ActivityShareImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/jpeg',
    );
    final incomplete = parser.parse(
      ActivitySharePayload(
        sharedText: 'Strava activity',
        images: [image],
        receivedAt: DateTime(2026, 8, 25),
      ),
    );
    final complete = parser.parse(
      ActivitySharePayload(
        sharedText: 'Strava\n5 km\n30:00\n2026-08-25 at 06:15',
        images: [image],
        receivedAt: DateTime(2026, 8, 25),
      ),
    );

    expect(incomplete.ocrFallbackRequired, isTrue);
    expect(complete.ocrFallbackRequired, isFalse);
  });
}
