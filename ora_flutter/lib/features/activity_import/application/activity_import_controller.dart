import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/apps_script_client.dart';
import '../../activity/domain/final_activity.dart';
import '../../dashboard/application/feature_controller.dart';
import '../data/activity_import_bridge_api.dart';
import '../data/activity_ocr_engine.dart';
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
    ActivityOcrEngine? ocrEngine,
    DateTime Function()? clock,
  }) : ocrEngine = ocrEngine ?? createActivityOcrEngine(),
       _clock = clock ?? DateTime.now;

  ActivityImportLaunch launch;
  final ActivityImportInbox inbox;
  final ActivityImportBridgeApi bridgeApi;
  final FeatureController featureController;
  final ActivityImportParser parser;
  final ActivityOcrEngine ocrEngine;
  final DateTime Function() _clock;

  ActivityImportPhase phase = ActivityImportPhase.reading;
  ActivityImportDraft? draft;
  ActivityImportErrorCode? errorCode;
  String? message;
  DateTime? _selectedDate;
  int? _selectedHour;
  int? _selectedMinute;
  bool _disposed = false;
  bool _ocrMetricsRead = false;

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
      if (!payload.hasData) {
        _fail(ActivityImportErrorCode.noSharedData);
        return;
      }
      String? ocrText;
      if (payload.images.isNotEmpty) {
        try {
          ocrText = await ocrEngine.recognize(payload.images.first);
        } on Object {
          ocrText = null;
        } finally {
          payload = await inbox.releaseImages(payload);
          launch = ActivityImportLaunch(token: token, payload: payload);
        }
      }
      final mergedText = [
        if (ocrText?.trim().isNotEmpty == true) ocrText!.trim(),
        if (payload.sharedText?.trim().isNotEmpty == true)
          payload.sharedText!.trim(),
      ].join('\n');
      if (mergedText.isNotEmpty) {
        payload = payload.copyWith(sharedText: mergedText);
      }
      final receivedAt = payload.receivedAt;
      _selectedDate = DateTime(
        receivedAt.year,
        receivedAt.month,
        receivedAt.day,
      );
      _selectedHour = receivedAt.hour;
      _selectedMinute = receivedAt.minute;
      var parsed = parser
          .parse(payload)
          .copyWith(
            startDateTime: DateTime(
              receivedAt.year,
              receivedAt.month,
              receivedAt.day,
              receivedAt.hour,
              receivedAt.minute,
            ),
            ocrFallbackRequired: false,
          );
      _ocrMetricsRead =
          parsed.distanceMeters != null && parsed.durationSeconds != null;
      await featureController.loadActivities(force: true);
      parsed = await _withDuplicateState(parsed);
      draft = parsed;
      phase = ActivityImportPhase.preview;
      if (!_ocrMetricsRead) {
        errorCode = ActivityImportErrorCode.ocrFailed;
        message = 'ACTIVITY DATA COULD NOT BE READ – SHARE AGAIN FROM STRAVA';
      } else if (parsed.exactDuplicate) {
        errorCode = ActivityImportErrorCode.possibleDuplicate;
        message = 'DUPLICATE ACTIVITY – ALREADY SAVED';
      } else if (parsed.source == ActivityImportSource.strava &&
          (parsed.sourceRef == null || parsed.sourceRef!.trim().isEmpty)) {
        errorCode = ActivityImportErrorCode.noActivityData;
        message = 'ACTIVITY SOURCE COULD NOT BE READ – SHARE AGAIN FROM STRAVA';
      } else if (!parsed.canSave) {
        errorCode = ActivityImportErrorCode.partialData;
        message = 'SELECT ACTIVITY DATE AND START TIME';
      }
      _safeNotify();
    } on BackendFailure catch (error) {
      _fail(_bridgeError(error.code));
    } on Object {
      _fail(ActivityImportErrorCode.backendError);
    }
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
    var value = draft;
    if (value != null) {
      value = await _withDuplicateState(value);
      draft = value;
    }
    if (value == null ||
        !_ocrMetricsRead ||
        !value.canSave ||
        phase == ActivityImportPhase.saving) {
      _refreshPreviewMessage();
      return false;
    }
    if (value.possibleDuplicate && !value.possibleDuplicateConfirmed) {
      errorCode = ActivityImportErrorCode.possibleDuplicate;
      message = 'POSSIBLE DUPLICATE – SAVE ANYWAY?';
      _safeNotify();
      return false;
    }
    final sourceRef = value.sourceRef?.trim();
    if (sourceRef == null || sourceRef.isEmpty) {
      errorCode = ActivityImportErrorCode.noActivityData;
      message = 'ACTIVITY SOURCE COULD NOT BE READ – SHARE AGAIN FROM STRAVA';
      _safeNotify();
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
          sourceRef: sourceRef,
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
        source: value.source.label,
        sourceRef: sourceRef,
        sourceUrl: value.sourceUrl,
      );
      final outcome = await featureController.saveAndSyncImportedActivity(
        activity,
      );
      if (outcome == ImportedActivitySaveOutcome.duplicate) {
        _fail(ActivityImportErrorCode.possibleDuplicate);
        message = 'DUPLICATE ACTIVITY – ALREADY SAVED';
        return false;
      }
      await _consumeTokenBestEffort();
      phase = ActivityImportPhase.saved;
      message = outcome == ImportedActivitySaveOutcome.synced
          ? 'SAVED & SYNCED'
          : 'SAVED LOCALLY – SYNC PENDING';
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

  void confirmPossibleDuplicate() {
    draft = draft?.copyWith(possibleDuplicateConfirmed: true);
    errorCode = null;
    message = null;
    _safeNotify();
  }

  Future<void> finish() async {
    await inbox.clear();
  }

  Future<void> decline() async {
    await _consumeTokenBestEffort();
    await inbox.clear();
    phase = ActivityImportPhase.cancelled;
    errorCode = ActivityImportErrorCode.importCancelled;
    message = 'IMPORT CANCELLED';
    _safeNotify();
  }

  Future<ActivityImportDraft> _withDuplicateState(
    ActivityImportDraft value,
  ) async {
    final sourceRef = value.sourceRef?.trim();
    final source = value.source.label;
    final localActivities = await featureController.activityStore.newestFirst(
      featureController.session.nik,
    );
    final activitiesById = <String, FinalActivity>{
      for (final activity in featureController.activities)
        activity.activityId: activity,
      for (final activity in localActivities) activity.activityId: activity,
    };
    final activities = activitiesById.values;
    final exactDuplicate =
        sourceRef != null &&
        sourceRef.isNotEmpty &&
        activities.any(
          (activity) =>
              activity.source.trim().toUpperCase() == source &&
              activity.sourceRef == sourceRef,
        );
    final start = value.startDateTime;
    final distance = value.distanceMeters;
    final duration = value.durationSeconds;
    if (exactDuplicate ||
        start == null ||
        distance == null ||
        duration == null) {
      return value.copyWith(
        exactDuplicate: exactDuplicate,
        possibleDuplicate: false,
      );
    }
    final possibleDuplicate = activities.any((activity) {
      if (activity.source.trim().toUpperCase() != source ||
          activity.sourceRef == sourceRef) {
        return false;
      }
      final existingDate = DateTime.fromMillisecondsSinceEpoch(
        activity.startDateTimeMillis,
      );
      if (existingDate.year != start.year ||
          existingDate.month != start.month ||
          existingDate.day != start.day) {
        return false;
      }
      final distanceTolerance = (distance * 0.015).clamp(0.0, 200.0);
      return (activity.distanceMeters - distance).abs() <= distanceTolerance &&
          (activity.activeDurationMillis ~/ 1000 - duration).abs() <= 60;
    });
    return value.copyWith(
      exactDuplicate: false,
      possibleDuplicate: possibleDuplicate,
      possibleDuplicateConfirmed: possibleDuplicate
          ? value.possibleDuplicateConfirmed
          : false,
    );
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
    if (!_ocrMetricsRead) {
      errorCode = ActivityImportErrorCode.ocrFailed;
      message = 'ACTIVITY DATA COULD NOT BE READ – SHARE AGAIN FROM STRAVA';
    } else if (value?.exactDuplicate == true) {
      errorCode = ActivityImportErrorCode.possibleDuplicate;
      message = 'DUPLICATE ACTIVITY – ALREADY SAVED';
    } else if (value?.source == ActivityImportSource.strava &&
        (value?.sourceRef == null || value!.sourceRef!.trim().isEmpty)) {
      errorCode = ActivityImportErrorCode.noActivityData;
      message = 'ACTIVITY SOURCE COULD NOT BE READ – SHARE AGAIN FROM STRAVA';
    } else if (value == null || !value.canSave) {
      errorCode = ActivityImportErrorCode.partialData;
      message = 'SELECT ACTIVITY DATE AND START TIME';
    } else if (value.possibleDuplicate && !value.possibleDuplicateConfirmed) {
      errorCode = ActivityImportErrorCode.possibleDuplicate;
      message = 'POSSIBLE DUPLICATE – SAVE ANYWAY?';
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

String importedActivityId({
  required String ownerNik,
  required ActivityImportSource source,
  required String sourceRef,
}) {
  final canonical = [ownerNik, source.label, sourceRef.trim()].join('|');
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
