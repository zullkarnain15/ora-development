import 'activity_import_models.dart';
import 'activity_share_payload.dart';

class ActivityImportParser {
  const ActivityImportParser();

  ActivityImportDraft parse(ActivitySharePayload payload) {
    final sharedText = payload.sharedText?.trim() ?? '';
    final extractedUrl = _extractUrl(sharedText);
    final sharedUrl = _nonEmpty(payload.sharedUrl) ?? extractedUrl;
    final source = _detectSource(payload.sourceHint, sharedUrl, sharedText);
    final distance = _parseDistance(sharedText);
    final duration = _parseDuration(sharedText);
    final detectedPace = _parsePace(sharedText);
    final start = _parseStartDateTime(sharedText);
    return ActivityImportDraft(
      source: source,
      payload: payload.copyWith(sharedUrl: sharedUrl),
      distanceMeters: distance,
      durationSeconds: duration,
      detectedPaceSecondsPerKm: detectedPace,
      startDateTime: start,
      ocrFallbackRequired:
          (distance == null || duration == null || start == null) &&
          payload.images.isNotEmpty,
    );
  }

  ActivityImportSource _detectSource(String? hint, String? url, String text) {
    final hinted = ActivityImportSourceValue.parse(hint);
    if (hinted != ActivityImportSource.unknown) return hinted;
    final haystack = '${url ?? ''}\n$text'.toLowerCase();
    if (haystack.contains('strava')) return ActivityImportSource.strava;
    if (haystack.contains('garmin')) return ActivityImportSource.garmin;
    if (haystack.contains('coros')) return ActivityImportSource.coros;
    if (haystack.contains('suunto')) return ActivityImportSource.suunto;
    if (haystack.contains('huawei')) return ActivityImportSource.huawei;
    if (haystack.contains('amazfit')) return ActivityImportSource.amazfit;
    return ActivityImportSource.unknown;
  }

  double? _parseDistance(String text) {
    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(km|kilomet(?:er|re)s?|m)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) return null;
    return match.group(2)!.toLowerCase() == 'm' ? value : value * 1000;
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

  String? _extractUrl(String text) => RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  ).firstMatch(text)?.group(0)?.replaceAll(RegExp(r'[),.;]+$'), '');

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
