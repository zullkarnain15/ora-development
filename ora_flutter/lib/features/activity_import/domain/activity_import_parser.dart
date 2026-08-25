import 'activity_import_models.dart';
import 'activity_share_payload.dart';
import 'activity_source_reference.dart';

class ActivityImportParser {
  const ActivityImportParser();

  ActivityImportDraft parse(ActivitySharePayload payload) {
    final sharedText = payload.sharedText?.trim() ?? '';
    final sharedUrls = _extractUrls(sharedText);
    final sharedUrl = _preferredStravaUrl([
      ?_nonEmpty(payload.sharedUrl),
      ...sharedUrls,
    ]);
    final source = _detectSource(payload.sourceHint, sharedText, sharedUrl);
    final distance = _parseDistance(sharedText);
    final detectedPace = _parsePace(sharedText);
    final duration =
        _parseDuration(sharedText) ??
        _durationFromDistanceAndPace(distance, detectedPace);
    final start = _parseStartDateTime(sharedText);
    final sourceReference = source == ActivityImportSource.strava
        ? extractStravaSourceReference(sharedUrl)
        : null;
    return ActivityImportDraft(
      source: source,
      payload: payload.copyWith(sharedUrl: sharedUrl),
      distanceMeters: distance,
      durationSeconds: duration,
      detectedPaceSecondsPerKm: detectedPace,
      sourceRef: sourceReference?.ref,
      sourceUrl: sourceReference?.url ?? sharedUrl,
      startDateTime: start,
      ocrFallbackRequired:
          (distance == null || duration == null || start == null) &&
          payload.images.isNotEmpty,
    );
  }

  ActivityImportSource _detectSource(String? hint, String text, String? url) {
    final hinted = ActivityImportSourceValue.parse(hint);
    if (hinted != ActivityImportSource.unknown) return hinted;
    final textSource = _sourceIn(text);
    if (textSource != ActivityImportSource.unknown) return textSource;
    return _sourceIn(url ?? '');
  }

  ActivityImportSource _sourceIn(String value) {
    final haystack = value.toLowerCase();
    if (haystack.contains('strava')) return ActivityImportSource.strava;
    if (haystack.contains('garmin')) return ActivityImportSource.garmin;
    if (haystack.contains('coros')) return ActivityImportSource.coros;
    if (haystack.contains('suunto')) return ActivityImportSource.suunto;
    if (haystack.contains('huawei')) return ActivityImportSource.huawei;
    if (haystack.contains('amazfit')) return ActivityImportSource.amazfit;
    return ActivityImportSource.unknown;
  }

  double? _parseDistance(String text) {
    final kilometers = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:k\s*m|kilomet(?:er|re)s?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    final kilometersValue = _positiveNumber(kilometers?.group(1));
    if (kilometersValue != null) return kilometersValue * 1000;

    final labeledMeters = RegExp(
      r'distance\D{0,24}?(\d+(?:[.,]\d+)?)\s*m\b',
      caseSensitive: false,
    ).firstMatch(text);
    final labeledMetersValue = _positiveNumber(labeledMeters?.group(1));
    if (labeledMetersValue != null) return labeledMetersValue;

    final genericMeters = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*m\b',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in genericMeters) {
      final value = _positiveNumber(match.group(1));
      // A plain `38m 47s` is duration. Unlabelled metre distances in a
      // Strava card are normally at least three digits.
      if (value != null && value >= 100) return value;
    }
    return null;
  }

  double? _positiveNumber(String? value) {
    final parsed = double.tryParse((value ?? '').replaceAll(',', '.'));
    return parsed == null || !parsed.isFinite || parsed <= 0 ? null : parsed;
  }

  int? _parseDuration(String text) {
    final words = RegExp(
      r'(?:(\d+)\s*(?:h|hours?)\b\s*)?(?:(\d+)\s*(?:m|minutes?)\b\s*)?(?:(\d+)\s*(?:s|seconds?)\b)?',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in words) {
      if (match.group(0)!.trim().isEmpty) continue;
      final hours = int.tryParse(match.group(1) ?? '') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
      final total = hours * 3600 + minutes * 60 + seconds;
      if (total > 0) return total;
    }

    for (final match in RegExp(
      r'(?<!\d)(\d{1,2}):([0-5]\d)(?::([0-5]\d))?(?!\s*/\s*km)',
      caseSensitive: false,
    ).allMatches(text)) {
      final first = int.parse(match.group(1)!);
      final second = int.parse(match.group(2)!);
      final third = int.tryParse(match.group(3) ?? '');
      final total = third == null
          ? first * 60 + second
          : first * 3600 + second * 60 + third;
      if (total > 0) return total;
    }
    return null;
  }

  int? _parsePace(String text) {
    final match = RegExp(
      r'(?<!\d)(\d{1,2}):([0-5]\d)\s*(?:/|per\s*)km\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  int? _durationFromDistanceAndPace(double? distanceMeters, int? pace) {
    if (distanceMeters == null ||
        distanceMeters <= 0 ||
        pace == null ||
        pace <= 0) {
      return null;
    }
    final duration = (pace * distanceMeters / 1000).round();
    return duration > 0 ? duration : null;
  }

  DateTime? _parseStartDateTime(String text) {
    DateTime? date;
    final iso = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})\b').firstMatch(text);
    if (iso != null) {
      date = _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    } else {
      final named = RegExp(
        r'\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(20\d{2})\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (named != null) {
        date = _safeDate(
          int.parse(named.group(3)!),
          _months[named.group(2)!.substring(0, 3).toLowerCase()]!,
          int.parse(named.group(1)!),
        );
      }
    }
    if (date == null) return null;

    final time = RegExp(
      r'\b(?:start(?:ed)?(?:\s+time)?|at)\s+(\d{1,2})[:.](\d{2})(?:\s*(am|pm))?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (time == null) return null;
    var hour = int.parse(time.group(1)!);
    final minute = int.parse(time.group(2)!);
    final meridiem = time.group(3)?.toLowerCase();
    if (minute > 59 || hour > (meridiem == null ? 23 : 12)) return null;
    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _safeDate(int year, int month, int day) {
    final value = DateTime(year, month, day);
    return value.year == year && value.month == month && value.day == day
        ? value
        : null;
  }

  List<String> _extractUrls(String text) =>
      RegExp(r'https?://[^\s]+', caseSensitive: false)
          .allMatches(text)
          .map((match) {
            return match.group(0)!.replaceAll(RegExp(r'[\]),.;]+$'), '');
          })
          .toList(growable: false);

  String? _preferredStravaUrl(List<String> values) {
    if (values.isEmpty) return null;
    for (final value in values) {
      final uri = Uri.tryParse(value);
      if (uri != null &&
          uri.pathSegments.any(
            (segment) => segment.toLowerCase() == 'activities',
          ) &&
          extractStravaSourceReference(value) != null) {
        return value;
      }
    }
    for (final value in values) {
      if (extractStravaSourceReference(value) != null) return value;
    }
    return values.first;
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
}
