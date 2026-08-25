import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/apps_script_client.dart';
import '../../activity/domain/final_activity.dart';
import '../../dashboard/application/feature_controller.dart';
import '../data/activity_import_bridge_api.dart';
import '../domain/activity_import_models.dart';
import '../domain/activity_import_parser.dart';
import '../domain/activity_share_payload.dart';
import 'activity_import_inbox.dart';

enum ActivityImportPhase { reading, preview, saving, saved, cancelled, error }

class ActivityImportController extends ChangeNotifier {
  ActivityImportController({
    required this.launch,
    required this.inbox,
    required this.bridgeApi,
    required this.featureController,
    this.parser = const ActivityImportParser(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ActivityImportLaunch launch;
  final ActivityImportInbox inbox;
  final ActivityImportBridgeApi bridgeApi;
  final FeatureController featureController;
  final ActivityImportParser parser;
  final DateTime Function() _clock;

  ActivityImportPhase phase = ActivityImportPhase.reading;
  ActivityImportDraft? draft;
  ActivityImportErrorCode? errorCode;
  String? message;
  DateTime? _selectedDate;
  int? _selectedHour;
  int? _selectedMinute;
  bool _disposed = false;

  DateTime? get selectedDate => _selectedDate;
  int? get selectedHour => _selectedHour;
  int? get selectedMinute => _selectedMinute;

  Future<void> initialize() async {
    phase = ActivityImportPhase.reading;
    errorCode = null;
    message = null;
    _safeNotify();
    try {
      var payload = launch.payload;
      final token = launch.token;
      if (token != null) payload = await bridgeApi.fetchTemporaryPayload(token);
      payload ??= ActivitySharePayload(receivedAt: _clock());
      if (!payload.hasData && !launch.manual) {
        _fail(ActivityImportErrorCode.noSharedData);
        return;
      }
      var parsed = parser.parse(payload);
      parsed = parsed.copyWith(
        possibleDuplicate: await _isPossibleDuplicate(parsed),
      );
      _adoptParsedStart(parsed.startDateTime);
      draft = parsed;
      phase = ActivityImportPhase.preview;
      if (parsed.ocrFallbackRequired) {
        errorCode = ActivityImportErrorCode.ocrNotAvailable;
        message = 'OCR NOT AVAILABLE - REVIEW THE FIELDS MANUALLY';
      } else if (!parsed.canSave) {
        errorCode = ActivityImportErrorCode.partialData;
        message = 'COMPLETE THE REQUIRED FIELDS';
      }
      _safeNotify();
    } on BackendFailure catch (error) {
      _fail(_bridgeError(error.code));
    } on Object {
      _fail(ActivityImportErrorCode.backendError);
    }
  }

  Future<void> replaceSharedText(String value) async {
    final current = draft?.payload ?? launch.payload;
    final payload = (current ?? ActivitySharePayload(receivedAt: _clock()))
        .copyWith(sharedText: value);
    var parsed = parser.parse(payload);
    parsed = parsed.copyWith(
      startDateTime: draft?.startDateTime,
      distanceMeters: parsed.distanceMeters ?? draft?.distanceMeters,
      durationSeconds: parsed.durationSeconds ?? draft?.durationSeconds,
      possibleDuplicate: await _isPossibleDuplicate(parsed),
    );
    _adoptParsedStart(parsed.startDateTime);
    draft = parsed;
    _refreshPreviewMessage();
  }

  Future<void> addImage(ActivityShareImage image) async {
    final current = draft?.payload ?? launch.payload;
    final payload = (current ?? ActivitySharePayload(receivedAt: _clock()))
        .copyWith(images: [image]);
    draft = parser
        .parse(payload)
        .copyWith(
          distanceMeters: draft?.distanceMeters,
          durationSeconds: draft?.durationSeconds,
          startDateTime: draft?.startDateTime,
          ocrFallbackRequired: true,
        );
    errorCode = ActivityImportErrorCode.ocrNotAvailable;
    message = 'SCREENSHOT ADDED - REVIEW THE FIELDS MANUALLY';
    phase = ActivityImportPhase.preview;
    _safeNotify();
  }

  void updateDistanceKm(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    draft = draft?.copyWith(
      distanceMeters: parsed == null ? null : parsed * 1000,
      clearDistance: parsed == null,
    );
    _refreshPreviewMessage();
  }

  void updateDuration(String value) {
    final parsed = parseEditableDuration(value);
    draft = draft?.copyWith(
      durationSeconds: parsed,
      clearDuration: parsed == null,
    );
    _refreshPreviewMessage();
  }

  void updateDate(DateTime value) {
    _selectedDate = DateTime(value.year, value.month, value.day);
    _composeSelectedStart();
    _refreshPreviewMessage();
  }

  void updateTime(int hour, int minute) {
    _selectedHour = hour;
    _selectedMinute = minute;
    _composeSelectedStart();
    _refreshPreviewMessage();
  }

  void _adoptParsedStart(DateTime? value) {
    if (value == null) return;
    _selectedDate = DateTime(value.year, value.month, value.day);
    _selectedHour = value.hour;
    _selectedMinute = value.minute;
  }

  void _composeSelectedStart() {
    final date = _selectedDate;
    final hour = _selectedHour;
    final minute = _selectedMinute;
    if (date == null || hour == null || minute == null) {
      draft = draft?.copyWith(clearStartDateTime: true);
      return;
    }
    draft = draft?.copyWith(
      startDateTime: DateTime(date.year, date.month, date.day, hour, minute),
    );
  }

  Future<bool> save() async {
    final value = draft;
    if (value == null ||
        !value.canSave ||
        phase == ActivityImportPhase.saving) {
      _refreshPreviewMessage();
      return false;
    }
    phase = ActivityImportPhase.saving;
    errorCode = null;
    message = null;
    _safeNotify();
    try {
      final start = value.startDateTime!;
      final durationMillis = value.durationSeconds! * 1000;
      final createdAt = _clock();
      final activity = FinalActivity(
        activityId: importedActivityId(
          ownerNik: featureController.session.nik,
          source: value.source,
          start: start,
          distanceMeters: value.distanceMeters!,
          durationSeconds: value.durationSeconds!,
          sourceUrl: value.payload.sharedUrl,
        ),
        ownerNik: featureController.session.nik,
        nicknameSnapshot: featureController.session.nickname,
        divisionGuildSnapshot: featureController.session.divisionGuild,
        startDateTimeMillis: start.millisecondsSinceEpoch,
        endDateTimeMillis: start.millisecondsSinceEpoch + durationMillis,
        distanceMeters: value.distanceMeters!,
        activeDurationMillis: durationMillis,
        averagePaceSecondsPerKm: value.calculatedPaceSecondsPerKm,
        createdAtMillis: createdAt.millisecondsSinceEpoch,
      );
      final inserted = await featureController.saveImportedActivity(activity);
      if (!inserted) {
        _fail(ActivityImportErrorCode.possibleDuplicate);
        return false;
      }
      await _consumeTokenBestEffort();
      await inbox.clear();
      phase = ActivityImportPhase.saved;
      message = 'ACTIVITY SAVED';
      _safeNotify();
      return true;
    } on BackendFailure {
      _fail(ActivityImportErrorCode.backendError);
      return false;
    } on Object {
      _fail(ActivityImportErrorCode.backendError);
      return false;
    }
  }

  Future<void> decline() async {
    await _consumeTokenBestEffort();
    await inbox.clear();
    phase = ActivityImportPhase.cancelled;
    errorCode = ActivityImportErrorCode.importCancelled;
    message = 'IMPORT CANCELLED';
    _safeNotify();
  }

  Future<bool> _isPossibleDuplicate(ActivityImportDraft value) async {
    final start = value.startDateTime;
    final distance = value.distanceMeters;
    final duration = value.durationSeconds;
    if (start == null || distance == null || duration == null) return false;
    final activities = await featureController.activityStore.newestFirst(
      featureController.session.nik,
    );
    return activities.any((activity) {
      final startDifference =
          (activity.startDateTimeMillis - start.millisecondsSinceEpoch).abs();
      final distanceTolerance = (distance * 0.015).clamp(50.0, 200.0);
      return startDifference <= const Duration(minutes: 2).inMilliseconds &&
          (activity.distanceMeters - distance).abs() <= distanceTolerance &&
          (activity.activeDurationMillis ~/ 1000 - duration).abs() <= 60;
    });
  }

  Future<void> _consumeTokenBestEffort() async {
    final token = launch.token;
    if (token == null) return;
    try {
      await bridgeApi.consumeTemporaryPayload(token);
    } on Object {
      // Expiry cleanup remains authoritative if consumption cannot be confirmed.
    }
  }

  void _refreshPreviewMessage() {
    final value = draft;
    phase = ActivityImportPhase.preview;
    if (value == null || !value.canSave) {
      errorCode = ActivityImportErrorCode.partialData;
      message = 'COMPLETE DISTANCE, DURATION, DATE, AND START TIME';
    } else if (value.possibleDuplicate) {
      errorCode = ActivityImportErrorCode.possibleDuplicate;
      message = 'POSSIBLE DUPLICATE - REVIEW BEFORE SAVING';
    } else if (value.paceStatus == ActivityImportPaceStatus.reviewRequired) {
      errorCode = ActivityImportErrorCode.partialData;
      message = 'PACE DOES NOT MATCH - REVIEW REQUIRED';
    } else {
      errorCode = null;
      message = null;
    }
    _safeNotify();
  }

  void _fail(ActivityImportErrorCode code) {
    phase = ActivityImportPhase.error;
    errorCode = code;
    message = activityImportErrorMessage(code);
    _safeNotify();
  }

  ActivityImportErrorCode _bridgeError(String? code) => switch (code) {
    'IMPORT_TOKEN_INVALID' => ActivityImportErrorCode.importTokenInvalid,
    'IMPORT_EXPIRED' => ActivityImportErrorCode.importExpired,
    'IMPORT_ALREADY_USED' => ActivityImportErrorCode.importAlreadyUsed,
    _ => ActivityImportErrorCode.backendError,
  };

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

int? parseEditableDuration(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2 && parts.length != 3) return null;
  final values = parts.map(int.tryParse).toList();
  if (values.any((item) => item == null || item < 0)) return null;
  if (parts.length == 2) {
    if (values[1]! > 59) return null;
    return values[0]! * 60 + values[1]!;
  }
  if (values[1]! > 59 || values[2]! > 59) return null;
  return values[0]! * 3600 + values[1]! * 60 + values[2]!;
}

String importedActivityId({
  required String ownerNik,
  required ActivityImportSource source,
  required DateTime start,
  required double distanceMeters,
  required int durationSeconds,
  String? sourceUrl,
}) {
  final canonical = [
    ownerNik,
    source.label,
    start.toUtc().toIso8601String(),
    distanceMeters.round(),
    durationSeconds,
    sourceUrl?.trim() ?? '',
  ].join('|');
  var hash = 5381;
  for (final codeUnit in canonical.codeUnits) {
    hash = (((hash << 5) + hash) ^ codeUnit) & 0x7fffffff;
  }
  return 'import_${source.name}_${hash.toRadixString(16)}';
}

String activityImportErrorMessage(
  ActivityImportErrorCode code,
) => switch (code) {
  ActivityImportErrorCode.importTokenInvalid => 'IMPORT LINK IS INVALID',
  ActivityImportErrorCode.importExpired => 'IMPORT LINK HAS EXPIRED',
  ActivityImportErrorCode.importAlreadyUsed => 'IMPORT LINK WAS ALREADY USED',
  ActivityImportErrorCode.noSharedData => 'NO SHARED ACTIVITY DATA',
  ActivityImportErrorCode.noActivityData => 'NO ACTIVITY DATA FOUND',
  ActivityImportErrorCode.partialData => 'COMPLETE THE REQUIRED FIELDS',
  ActivityImportErrorCode.ocrFailed => 'SCREENSHOT COULD NOT BE READ',
  ActivityImportErrorCode.ocrNotAvailable =>
    'OCR NOT AVAILABLE - REVIEW MANUALLY',
  ActivityImportErrorCode.invalidDistance => 'ENTER A VALID DISTANCE',
  ActivityImportErrorCode.invalidDuration => 'ENTER A VALID DURATION',
  ActivityImportErrorCode.startTimeRequired => 'START TIME IS REQUIRED',
  ActivityImportErrorCode.possibleDuplicate => 'POSSIBLE DUPLICATE ACTIVITY',
  ActivityImportErrorCode.backendError => 'IMPORT SERVICE IS UNAVAILABLE',
  ActivityImportErrorCode.importCancelled => 'IMPORT CANCELLED',
};
