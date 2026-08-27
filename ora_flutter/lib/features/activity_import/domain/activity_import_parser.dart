import 'activity_import_models.dart';
import 'activity_share_payload.dart';
import 'activity_source_reference.dart';

class _DurationParseResult {
  const _DurationParseResult({
    required this.seconds,
    this.derivedFromPace = false,
  });

  final int? seconds;
  final bool derivedFromPace;
}

class ActivityImportParser {
  const ActivityImportParser();

  ActivityImportDraft parse(ActivitySharePayload payload) {
    final sharedText = _normalizeOcrText(payload.sharedText?.trim() ?? '');
    final sharedUrls = _extractUrls(sharedText);
    final sharedUrl = _preferredStravaUrl([
      ?_nonEmpty(payload.sharedUrl),
      ...sharedUrls,
    ]);
    final source = _detectSource(payload.sourceHint, sharedText, sharedUrl);
    final distance = _parseDistance(sharedText);
    final detectedPace = _parsePace(sharedText);
    final duration = _parseDuration(
      sharedText,
      source: source,
      distanceMeters: distance,
      paceSecondsPerKm: detectedPace,
    );
    final start = _parseStartDateTime(sharedText);
    final sourceReference = source == ActivityImportSource.strava
        ? extractStravaSourceReference(sharedUrl)
        : null;
    return ActivityImportDraft(
      source: source,
      payload: payload.copyWith(sharedUrl: sharedUrl),
      distanceMeters: distance,
      durationSeconds: duration.seconds,
      detectedPaceSecondsPerKm: detectedPace,
      sourceRef: sourceReference?.ref,
      sourceUrl: sourceReference?.url ?? sharedUrl,
      startDateTime: start,
      ocrFallbackRequired:
          (distance == null || duration.seconds == null || start == null) &&
          payload.images.isNotEmpty,
      derivedFromPace: duration.derivedFromPace,
    );
  }

  ActivityImportSource _detectSource(String? hint, String text, String? url) {
    final hinted = ActivityImportSourceValue.parse(hint);
    if (hinted != ActivityImportSource.unknown) return hinted;
    final textSource = _sourceIn(text);
    if (textSource != ActivityImportSource.unknown) return textSource;
    if (RegExp(r'\btotal\s*time\b', caseSensitive: false).hasMatch(text)) {
      return ActivityImportSource.garmin;
    }
    if (_hasStravaMetricLabels(text)) return ActivityImportSource.strava;
    return _sourceIn(url ?? '');
  }

  bool _hasStravaMetricLabels(String text) =>
      RegExp(r'\bdistance\b', caseSensitive: false).hasMatch(text) &&
      RegExp(r'\bpace\b', caseSensitive: false).hasMatch(text) &&
      RegExp(r'\btime\b', caseSensitive: false).hasMatch(text);

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

  _DurationParseResult _parseDuration(
    String text, {
    required ActivityImportSource source,
    required double? distanceMeters,
    required int? paceSecondsPerKm,
  }) {
    if (source == ActivityImportSource.strava) {
      final labelled = _parseStravaTime(text);
      if (labelled != null &&
          _isConsistentStravaDuration(
            labelled,
            distanceMeters: distanceMeters,
            paceSecondsPerKm: paceSecondsPerKm,
          )) {
        return _DurationParseResult(seconds: labelled);
      }
      if (!_hasTimeLabel(text)) {
        final generic = _parseGenericDuration(text);
        if (generic != null &&
            _isConsistentStravaDuration(
              generic,
              distanceMeters: distanceMeters,
              paceSecondsPerKm: paceSecondsPerKm,
            )) {
          return _DurationParseResult(seconds: generic);
        }
      }
      final derived = _durationFromDistanceAndPace(
        distanceMeters,
        paceSecondsPerKm,
      );
      return _DurationParseResult(
        seconds: derived,
        derivedFromPace: derived != null,
      );
    }
    return _DurationParseResult(seconds: _parseGenericDuration(text));
  }

  bool _hasTimeLabel(String text) => RegExp(
    r'\b(?:moving\s*time|total\s*time|duration|time)\b',
    caseSensitive: false,
  ).hasMatch(text);

  int? _parseStravaTime(String text) {
    final labels = RegExp(
      r'\b(?:moving\s*time|total\s*time|duration|time)\b',
      caseSensitive: false,
    ).allMatches(text);
    for (final label in labels) {
      final valueEnd = (label.end + 72).clamp(0, text.length);
      var valueText = text.substring(label.end, valueEnd);
      final nextMetric = RegExp(
        r'\b(?:distance|pace|moving\s*time|total\s*time|duration|time)\b',
        caseSensitive: false,
      ).firstMatch(valueText);
      if (nextMetric != null) {
        valueText = valueText.substring(0, nextMetric.start);
      }
      final value = _durationIn(valueText, allowSingleMinute: true);
      if (value != null) return value;
    }
    return null;
  }

  bool _isConsistentStravaDuration(
    int duration, {
    required double? distanceMeters,
    required int? paceSecondsPerKm,
  }) {
    final expected = _durationFromDistanceAndPace(
      distanceMeters,
      paceSecondsPerKm,
    );
    return expected == null || (duration - expected).abs() <= 90;
  }

  int? _durationFromDistanceAndPace(
    double? distanceMeters,
    int? paceSecondsPerKm,
  ) {
    if (distanceMeters == null ||
        !distanceMeters.isFinite ||
        distanceMeters <= 0 ||
        paceSecondsPerKm == null ||
        paceSecondsPerKm <= 0) {
      return null;
    }
    return ((distanceMeters / 1000) * paceSecondsPerKm).round();
  }

  int? _parseGenericDuration(String text) {
    final labels = RegExp(
      r'\b(total\s*time|moving\s*time|duration|time)\b',
      caseSensitive: false,
    ).allMatches(text);
    for (final label in labels) {
      final prefix = text.substring(
        label.start > 8 ? label.start - 8 : 0,
        label.start,
      );
      if (RegExp(r'start(?:ed)?\s*$', caseSensitive: false).hasMatch(prefix)) {
        continue;
      }
      final end = (label.end + 96).clamp(0, text.length);
      final value = _durationIn(
        text.substring(label.end, end),
        allowSingleMinute: true,
      );
      if (value != null) return value;
    }

    return _durationIn(text, allowSingleMinute: false);
  }

  int? _durationIn(String text, {required bool allowSingleMinute}) {
    text = text.replaceAllMapped(
      RegExp(r'(\d)\s*[lI]\s*(?=s\b)'),
      (match) => '${match.group(1)}1',
    );
    final hours = RegExp(
      r'(?<!\d)(\d+)\s*(?:h|hours?)\b(?:\s*(\d+)\s*(?:m|minutes?)\b)?(?:\s*(\d+)\s*(?:s|seconds?)\b)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (hours != null) {
      final total =
          int.parse(hours.group(1)!) * 3600 +
          (int.tryParse(hours.group(2) ?? '') ?? 0) * 60 +
          (int.tryParse(hours.group(3) ?? '') ?? 0);
      if (total > 0) return total;
    }

    final minutesSeconds = RegExp(
      r'(?<!\d)(\d+)\s*(?:m|minutes?)\s*(\d+)\s*(?:s|seconds?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (minutesSeconds != null) {
      return int.parse(minutesSeconds.group(1)!) * 60 +
          int.parse(minutesSeconds.group(2)!);
    }

    if (allowSingleMinute) {
      final minutes = RegExp(
        r'(?<![\d.])(\d{1,3})\s*(?:m|minutes?)\b(?!\s*(?:\/|i|l|\|)\s*k\s*m)',
        caseSensitive: false,
      ).firstMatch(text);
      if (minutes != null) return int.parse(minutes.group(1)!) * 60;
    }

    for (final match in RegExp(
      r'(?<!\d)(\d{1,2}):([0-5]\d)(?::([0-5]\d))?',
    ).allMatches(text)) {
      final suffix = text.substring(
        match.end,
        (match.end + 12).clamp(0, text.length),
      );
      if (_paceSuffix.hasMatch(suffix)) continue;
      final prefix = text.substring(
        (match.start - 18).clamp(0, text.length),
        match.start,
      );
      if (RegExp(
        r'(?:\bat|start(?:ed)?(?:\s+time)?)\s*$',
        caseSensitive: false,
      ).hasMatch(prefix)) {
        continue;
      }
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
    final labeled = RegExp(
      r'\b(?:avg(?:erage)?\.?\s*)?pace\b[^\d]{0,20}(\d{1,2}):([0-5]\d)',
      caseSensitive: false,
    ).firstMatch(text);
    final match =
        labeled ??
        RegExp(
          r'(?<!\d)(\d{1,2}):([0-5]\d)\s*(?:(?:/|i|l|\|)\s*k\s*m|per\s*k\s*m)\b',
          caseSensitive: false,
        ).firstMatch(text);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  String _normalizeOcrText(String text) => text
      .replaceAll('\u2019', "'")
      .replaceAll('\u2032', "'")
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u2033', '"')
      .replaceAllMapped(
        RegExp(r"(?<!\d)(\d{1,2})\s*'\s*([0-5]\d)"),
        (match) => '${match.group(1)}:${match.group(2)}',
      );

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

  static final _paceSuffix = RegExp(
    r'^\s*(?:(?:/|i|l|\|)\s*k\s*m|per\s*k\s*m)\b',
    caseSensitive: false,
  );
}
