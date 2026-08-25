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
}
