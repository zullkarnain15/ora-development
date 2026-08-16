import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../activity/data/activity_store.dart';
import '../../activity/domain/final_activity.dart';
import '../../auth/domain/auth_models.dart';
import '../data/native_tracking_adapter.dart';
import '../data/tracking_adapter_factory.dart';
import '../domain/field_diagnostics.dart';
import '../domain/final_distance_reconciler.dart';
import '../domain/gps_soak.dart';
import '../domain/gps_soak_policy_factory.dart';
import '../domain/location_engine.dart';
import '../domain/run_time_engine.dart';
import '../domain/tracking_models.dart';
import '../domain/tracking_policy_factory.dart';

class TrackingController extends ChangeNotifier with WidgetsBindingObserver {
  TrackingController({
    required this.user,
    required this.store,
    TrackingNativeAdapter? nativeAdapter,
    TrackingPolicy? policy,
    GpsSoakPolicy? soakPolicy,
    Duration? gpsSearchTimeout,
    this.onActivitySaved,
  }) : nativeAdapter = nativeAdapter ?? createTrackingAdapter(),
       policy = policy ?? createTrackingPolicy(),
       soakPolicy = soakPolicy ?? createGpsSoakPolicy(),
       gpsSearchTimeout =
           gpsSearchTimeout ??
           (soakPolicy ?? createGpsSoakPolicy()).maximumSoakDuration,
       _locationEngine = RunLocationEngine(
         policy: policy ?? createTrackingPolicy(),
       ),
       _gpsSoakEngine = GpsSoakEngine(
         policy: soakPolicy ?? createGpsSoakPolicy(),
       ) {
    _processClock.start();
  }

  UserSession user;
  final ActivityStore store;
  final TrackingNativeAdapter nativeAdapter;
  final TrackingPolicy policy;
  final GpsSoakPolicy soakPolicy;
  final Duration gpsSearchTimeout;
  final VoidCallback? onActivitySaved;
  final RunLocationEngine _locationEngine;
  final GpsSoakEngine _gpsSoakEngine;
  final Stopwatch _processClock = Stopwatch();

  RunSession? session;
  FinalActivity? finalActivity;
  TrackingStatus status = TrackingStatus.idle;
  NativeTrackingStatus? nativeStatus;
  GpsQuality gpsQuality = GpsQuality.unknown;
  String message = 'GPS READY';
  bool isWarning = false;
  int activeDurationMillis = 0;
  int sessionElapsedMillis = 0;
  double distanceMeters = 0;
  int? averagePace;
  int gpsSearchRemainingSeconds = 20;
  bool gpsSearchTimedOut = false;
  GpsSoakResult? gpsSoakResult;
  ReconciliationResult? finalReconciliation;
  FieldDiagnosticSummary? fieldDiagnostics;

  StreamSubscription<NativeTrackingEvent>? _eventSubscription;
  Timer? _ticker;
  NativeClockSnapshot? _nativeClockAnchor;
  int _processAnchorMillis = 0;
  int? _lastRawMonotonicMillis;
  int _lastPersistedCheckpoint = 0;
  int _eventSequence = 0;
  Future<void> _eventWork = Future.value();
  Future<void> _commandQueue = Future.value();
  bool _initialized = false;
  bool _disposed = false;
  bool _runVisible = false;
  RawLocationSample? _readySample;
  int? _gpsSearchDeadlineProcessMillis;
  GpsSoakState? _lastSoakState;
  int _gpsStatusChanges = 0;

  bool get hasActiveSession =>
      session != null &&
      status != TrackingStatus.idle &&
      status != TrackingStatus.finished &&
      status != TrackingStatus.error;
  bool get isBackgroundTracking => nativeStatus?.serviceActive ?? false;
  TrackingDiagnostics get diagnostics => _locationEngine.diagnostics;
  bool get canStartAnyway =>
      session == null &&
      status == TrackingStatus.preparingGps &&
      gpsSearchTimedOut &&
      nativeStatus?.permission == LocationPermissionState.precise &&
      nativeStatus?.locationEnabled == true;

  void updateUser(UserSession value) {
    if (value.nik != user.nik) return;
    user = value;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _eventSubscription = nativeAdapter.events.listen(
      (event) {
        _eventWork = _eventWork.then((_) => _handleNativeEvent(event));
      },
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('ORA_RUN native event stream error: ${error.runtimeType}');
        }
      },
    );
    try {
      await _refreshNativeState();
    } on NativeTrackingFailure catch (error) {
      message = error.message;
      isWarning = true;
    }
    final recoverable = await store.recoverableRun(user.nik);
    if (recoverable != null) {
      final nativeCheckpoint = nativeStatus?.lastActiveMonotonicMillis;
      final canTrustNativeCheckpoint =
          recoverable.status == TrackingStatus.running &&
          nativeStatus?.serviceActive == true &&
          nativeStatus?.trackingState == 'tracking' &&
          nativeStatus?.sessionId == recoverable.sessionId &&
          nativeCheckpoint != null &&
          _nativeClockAnchor != null &&
          RunTimeEngine.sameBoot(
            recoverable.bootEpochMillis,
            _nativeClockAnchor!.bootEpochMillis,
          );
      final boundedCheckpoint = canTrustNativeCheckpoint
          ? nativeCheckpoint.clamp(
              recoverable.lastCheckpointMonotonicMillis,
              _nativeClockAnchor!.monotonicMillis,
            )
          : recoverable.lastCheckpointMonotonicMillis;
      session = recoverable.copyWith(
        lastCheckpointMonotonicMillis: boundedCheckpoint,
      );
      status = TrackingStatus.recoverableSession;
      distanceMeters = recoverable.distanceMeters;
      activeDurationMillis = RunTimeEngine.activeDurationAt(
        session!,
        boundedCheckpoint,
        _nativeClockAnchor?.bootEpochMillis ?? recoverable.bootEpochMillis,
      );
      message = 'UNFINISHED ADVENTURE FOUND';
      isWarning = true;
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    _safeNotify();
  }

  void setRunVisible(bool visible) {
    _runVisible = visible;
    if (visible && session == null) {
      unawaited(prepareGps());
    } else if (!visible && session == null) {
      unawaited(_enqueueCommand(_cancelPrepare));
    }
  }

  Future<void> prepareGps() => _enqueueCommand(_prepareGps);

  Future<void> _prepareGps() async {
    if (session != null || status == TrackingStatus.finalizing) return;
    status = TrackingStatus.preparingGps;
    message = 'WAITING FOR GPS';
    isWarning = false;
    gpsQuality = GpsQuality.unknown;
    gpsSearchRemainingSeconds = (gpsSearchTimeout.inMilliseconds / 1000).ceil();
    gpsSearchTimedOut = false;
    _gpsSearchDeadlineProcessMillis = null;
    _readySample = null;
    gpsSoakResult = null;
    finalReconciliation = null;
    fieldDiagnostics = null;
    _lastSoakState = GpsSoakState.searching;
    _gpsStatusChanges = 1;
    _gpsSoakEngine.reset();
    _safeNotify();
    try {
      final permissions = await nativeAdapter.requestPermission();
      nativeStatus = permissions;
      if (permissions.permission == LocationPermissionState.approximate) {
        _failBeforeStart(
          'PRECISE LOCATION REQUIRED - ENABLE PRECISE IN APP SETTINGS',
        );
        return;
      }
      if (permissions.permission != LocationPermissionState.precise) {
        _failBeforeStart('LOCATION PERMISSION REQUIRED');
        return;
      }
      if (!permissions.locationEnabled) {
        _failBeforeStart('TURN ON LOCATION SERVICES TO CONTINUE');
        return;
      }
      await nativeAdapter.prepare();
      _gpsSearchDeadlineProcessMillis =
          _processClock.elapsedMilliseconds + gpsSearchTimeout.inMilliseconds;
      message = 'WAITING FOR GPS - MOVE TO AN OPEN AREA';
      _safeNotify();
    } on Object catch (error) {
      _showNativeError(error);
      status = TrackingStatus.idle;
    }
  }

  Future<void> _cancelPrepare() async {
    if (session != null) return;
    try {
      await nativeAdapter.cancelPrepare();
    } on Object {
      // Preview is best-effort and never owns a run session.
    }
    _gpsSoakEngine.reset();
    _readySample = null;
    _gpsSearchDeadlineProcessMillis = null;
    gpsSearchTimedOut = false;
    gpsSearchRemainingSeconds = (gpsSearchTimeout.inMilliseconds / 1000).ceil();
    if (status == TrackingStatus.preparingGps ||
        status == TrackingStatus.gpsReady) {
      status = TrackingStatus.idle;
      message = 'PREPARE GPS TO START';
      gpsQuality = GpsQuality.unknown;
      isWarning = false;
      _safeNotify();
    }
  }

  Future<void> start() => _enqueueCommand(() => _start());

  Future<void> startAnyway() =>
      _enqueueCommand(() => _start(allowWithoutGps: true));

  Future<void> cancelGpsPreparation() => _enqueueCommand(_cancelPrepare);

  Future<void> _start({bool allowWithoutGps = false}) async {
    final hasReadyFix =
        status == TrackingStatus.gpsReady && _readySample != null;
    if (hasActiveSession ||
        (!hasReadyFix && !(allowWithoutGps && canStartAnyway))) {
      return;
    }
    final previousStatus = status;
    status = TrackingStatus.startRequested;
    message = 'CHECKING LOCATION';
    isWarning = false;
    finalActivity = null;
    _gpsSearchDeadlineProcessMillis = null;
    _safeNotify();
    try {
      final permissions = nativeStatus!;
      final now = await _takeNativeSnapshot();
      final id = 'ora_${now.epochMillis}_${now.monotonicMillis}';
      var run = RunSession(
        sessionId: id,
        ownerNik: user.nik,
        nicknameSnapshot: user.nickname,
        divisionGuildSnapshot: user.divisionGuild,
        status: TrackingStatus.startRequested,
        policyVersion: policy.version,
        startEpochMillis: now.epochMillis,
        startMonotonicMillis: now.monotonicMillis,
        bootEpochMillis: now.bootEpochMillis,
        activeAccumulatedMillis: 0,
        lastCheckpointMonotonicMillis: now.monotonicMillis,
        distanceMeters: 0,
        acceptedPoints: 0,
        rejectedPoints: 0,
        createdAtMillis: now.epochMillis,
        updatedAtMillis: now.epochMillis,
      );
      await store.createRun(
        run,
        _event(
          id,
          'START_REQUESTED',
          previousStatus,
          TrackingStatus.startRequested,
          now,
        ),
      );
      session = run;
      _locationEngine.startNewSession();
      await nativeAdapter.cancelPrepare();
      await nativeAdapter.start(id);
      run = RunTimeEngine.enterRunning(run, now);
      await store.updateRun(
        run,
        _event(
          id,
          'NATIVE_SERVICE_STARTED',
          TrackingStatus.startRequested,
          TrackingStatus.running,
          now,
          details: permissions.notificationGranted
              ? null
              : 'notification_permission_denied',
        ),
      );
      session = run;
      status = TrackingStatus.running;
      message = allowWithoutGps
          ? 'RUNNING - WAITING FOR GPS'
          : permissions.notificationGranted
          ? 'GPS TRACKING ACTIVE'
          : 'GPS TRACKING ACTIVE - NOTIFICATIONS DISABLED';
      isWarning = allowWithoutGps || !permissions.notificationGranted;
      _lastRawMonotonicMillis = null;
      _readySample = null;
      _safeNotify();
      await _refreshNativeStatusOnly();
    } on Object catch (error) {
      await _handleStartFailure(error);
    }
  }

  Future<void> pause() => _enqueueCommand(_pause);

  Future<void> _pause() async {
    final current = session;
    if (current == null || status != TrackingStatus.running) {
      return;
    }
    try {
      await nativeAdapter.pause(current.sessionId);
      final now = await _takeNativeSnapshot();
      final paused = current.status == TrackingStatus.running
          ? RunTimeEngine.pause(current, now)
          : current.copyWith(
              status: TrackingStatus.paused,
              clearActiveAnchor: true,
              lastCheckpointMonotonicMillis: now.monotonicMillis,
              updatedAtMillis: now.epochMillis,
            );
      _locationEngine.pause();
      await store.updateRun(
        paused,
        _event(
          current.sessionId,
          'PAUSED',
          current.status,
          TrackingStatus.paused,
          now,
        ),
      );
      session = paused;
      status = TrackingStatus.paused;
      activeDurationMillis = paused.activeAccumulatedMillis;
      message = 'ADVENTURE PAUSED';
      isWarning = false;
      _safeNotify();
      await _refreshNativeStatusOnly();
    } on Object catch (error) {
      _showNativeError(error);
    }
  }

  Future<void> resume() => _enqueueCommand(_resume);

  Future<void> _resume() async {
    final current = session;
    if (current == null || status != TrackingStatus.paused) return;
    try {
      await nativeAdapter.resume(current.sessionId);
      final now = await _takeNativeSnapshot();
      final resumed = RunTimeEngine.enterRunning(current, now);
      _locationEngine.resume();
      await store.updateRun(
        resumed,
        _event(
          current.sessionId,
          'RESUMED',
          TrackingStatus.paused,
          TrackingStatus.running,
          now,
        ),
      );
      session = resumed;
      status = TrackingStatus.running;
      message = 'ACTIVE - WAITING FOR A FRESH GPS FIX';
      isWarning = true;
      _lastRawMonotonicMillis = null;
      _safeNotify();
      await _refreshNativeStatusOnly();
    } on Object catch (error) {
      _showNativeError(error);
    }
  }

  Future<void> finish() => _enqueueCommand(_finish);

  Future<void> _finish() async {
    final current = session;
    if (current == null ||
        status == TrackingStatus.finalizing ||
        status == TrackingStatus.finished) {
      return;
    }
    status = TrackingStatus.finalizing;
    message = 'SAVING ADVENTURE';
    isWarning = false;
    _safeNotify();
    try {
      await nativeAdapter.stop(current.sessionId);
    } on Object {
      // Finalization is local-first; a stopped/missing native service is safe.
    }
    try {
      final now = await _takeNativeSnapshot();
      var finalized = current.status == TrackingStatus.running
          ? RunTimeEngine.pause(current, now)
          : current;
      finalized = finalized.copyWith(
        status: TrackingStatus.finalizing,
        endEpochMillis: now.epochMillis,
        clearActiveAnchor: true,
        lastCheckpointMonotonicMillis: now.monotonicMillis,
        updatedAtMillis: now.epochMillis,
      );
      await store.updateRun(
        finalized,
        _event(
          current.sessionId,
          'FINALIZING',
          current.status,
          TrackingStatus.finalizing,
          now,
        ),
      );
      final points = await store.pointDecisions(
        finalized.sessionId,
        finalized.ownerNik,
      );
      final reconciliation = const FinalDistanceReconciler().reconcile(points);
      final saved = await store.finalizeRun(
        finalized,
        finalDistanceMeters: reconciliation.finalDistanceMeters,
      );
      final soak = gpsSoakResult;
      final summary = FieldDiagnosticSummary.fromDecisions(
        source: kIsWeb ? 'WEB' : 'ANDROID',
        decisions: points,
        soakDurationMillis: soak?.elapsed.inMilliseconds ?? 0,
        soakSampleCount: soak?.sampleCount ?? 0,
        gpsStatusChanges: _gpsStatusChanges,
        finalDistanceMeters: saved.distanceMeters,
        flags: reconciliation.flags,
      );
      finalReconciliation = reconciliation;
      fieldDiagnostics = summary;
      finalActivity = saved;
      session = finalized.copyWith(
        status: TrackingStatus.finished,
        distanceMeters: saved.distanceMeters,
        finalActivityId: saved.activityId,
      );
      status = TrackingStatus.finished;
      activeDurationMillis = saved.activeDurationMillis;
      distanceMeters = saved.distanceMeters;
      averagePace = saved.averagePaceSecondsPerKm;
      message = 'ADVENTURE SAVED OFFLINE';
      isWarning = false;
      _locationEngine.stop();
      if (kDebugMode) debugPrint('ORA_RUN_SUMMARY\n${summary.formatForLog()}');
      onActivitySaved?.call();
      _safeNotify();
      await _refreshNativeStatusOnly();
    } on Object {
      status = TrackingStatus.recoverableSession;
      message = 'SAVE INTERRUPTED - RECOVERY AVAILABLE';
      isWarning = true;
      _safeNotify();
    }
  }

  Future<void> resumeRecovered() => _enqueueCommand(_resumeRecovered);

  Future<void> _resumeRecovered() async {
    final current = session;
    if (current == null || status != TrackingStatus.recoverableSession) return;
    try {
      final now = await _takeNativeSnapshot();
      final recovered = RunTimeEngine.enterRunning(
        RunTimeEngine.recoverForReacquisition(current, now),
        now,
      );
      _locationEngine.restore(distanceMeters: current.distanceMeters);
      await nativeAdapter.start(current.sessionId);
      await store.updateRun(
        recovered,
        _event(
          current.sessionId,
          'RECOVERY_RESUMED',
          current.status,
          TrackingStatus.running,
          now,
          details:
              RunTimeEngine.sameBoot(
                current.bootEpochMillis,
                now.bootEpochMillis,
              )
              ? 'same_boot'
              : 'reboot_boundary',
        ),
      );
      session = recovered;
      status = TrackingStatus.running;
      activeDurationMillis = recovered.activeAccumulatedMillis;
      distanceMeters = recovered.distanceMeters;
      message = 'RECOVERED - ACTIVE, WAITING FOR GPS';
      isWarning = true;
      _lastRawMonotonicMillis = null;
      _safeNotify();
      await _refreshNativeStatusOnly();
    } on Object catch (error) {
      _showNativeError(error);
    }
  }

  Future<void> endRecoveredAndSave() => _enqueueCommand(_endRecoveredAndSave);

  Future<void> _endRecoveredAndSave() async {
    final current = session;
    if (current == null || status != TrackingStatus.recoverableSession) return;
    final now = await _takeNativeSnapshot();
    session = RunTimeEngine.recoverForReacquisition(current, now);
    status = TrackingStatus.reacquiring;
    await _finish();
  }

  Future<void> discardRecovered() => _enqueueCommand(_discardRecovered);

  Future<void> _discardRecovered() async {
    final current = session;
    if (current == null || status != TrackingStatus.recoverableSession) return;
    try {
      await nativeAdapter.stop(current.sessionId);
    } on Object {
      // The local confirmed discard remains authoritative.
    }
    await store.discardRun(current.sessionId, user.nik);
    session = null;
    status = TrackingStatus.idle;
    distanceMeters = 0;
    activeDurationMillis = 0;
    sessionElapsedMillis = 0;
    averagePace = null;
    finalReconciliation = null;
    fieldDiagnostics = null;
    message = 'GPS READY';
    isWarning = false;
    _locationEngine.stop();
    _safeNotify();
  }

  void done() {
    if (status != TrackingStatus.finished) return;
    session = null;
    finalActivity = null;
    status = TrackingStatus.idle;
    distanceMeters = 0;
    activeDurationMillis = 0;
    sessionElapsedMillis = 0;
    averagePace = null;
    finalReconciliation = null;
    fieldDiagnostics = null;
    gpsQuality = GpsQuality.unknown;
    message = 'GPS READY';
    isWarning = false;
    _safeNotify();
    if (_runVisible) {
      unawaited(prepareGps());
    }
  }

  Future<void> _handleNativeEvent(NativeTrackingEvent event) async {
    if (_disposed) return;
    if (event.type == 'location' && event.sample != null) {
      await _handleLocation(event.sample!);
      return;
    }
    if (event.type == 'providerUnavailable') {
      _gpsStatusChanges += 1;
      _showGpsWarning('ACTIVE DURATION CONTINUES - WAITING FOR GPS');
      return;
    }
    if (event.type == 'error') {
      _gpsStatusChanges += 1;
      message = _messageForNativeCode(event.code, event.message);
      isWarning = true;
      _safeNotify();
      return;
    }
    if (event.type == 'serviceState') {
      await _refreshNativeStatusOnly();
    }
  }

  Future<void> _handleLocation(RawLocationSample point) async {
    final current = session;
    if (current == null &&
        (status == TrackingStatus.preparingGps ||
            status == TrackingStatus.gpsReady)) {
      gpsQuality = point.quality(policy);
      final soak = _gpsSoakEngine.add(point);
      _recordSoakState(soak.state);
      gpsSoakResult = soak;
      if (soak.state == GpsSoakState.ready) {
        _readySample = soak.latestSample;
        status = TrackingStatus.gpsReady;
        message = 'GPS READY - YOU CAN START';
        isWarning = false;
        _gpsSearchDeadlineProcessMillis = null;
        gpsSearchTimedOut = false;
        gpsSearchRemainingSeconds = 0;
      } else {
        _readySample = null;
        status = TrackingStatus.preparingGps;
        if (!gpsSearchTimedOut) {
          message = soak.validSampleCount == 0
              ? 'SEARCHING GPS - MOVE TO AN OPEN AREA'
              : 'STABILIZING GPS - HOLD POSITION BRIEFLY';
          isWarning = false;
        }
      }
      _safeNotify();
      return;
    }
    if (current == null ||
        (status != TrackingStatus.acquiringGps &&
            status != TrackingStatus.reacquiring &&
            status != TrackingStatus.running)) {
      return;
    }
    _lastRawMonotonicMillis = point.receivedMonotonicMillis;
    gpsQuality = point.quality(policy);
    final decision = _locationEngine.process(point);
    var updated = current.copyWith(
      distanceMeters: _locationEngine.totalDistanceMeters,
      acceptedPoints: _locationEngine.diagnostics.acceptedPoints,
      rejectedPoints: _locationEngine.diagnostics.rejectedPoints,
      lastRejectReason: decision.reason?.value,
      clearRejectReason: decision.reason == null,
      lastCheckpointMonotonicMillis: point.receivedMonotonicMillis,
      updatedAtMillis: point.epochMillis,
    );
    if (decision.type == LocationDecisionType.baseline ||
        decision.type == LocationDecisionType.reentryBaseline) {
      message = 'GPS TRACKING ACTIVE';
      isWarning = false;
    } else if (decision.type == LocationDecisionType.rejected) {
      _applyRejectionMessage(decision.reason);
    } else if (status == TrackingStatus.running) {
      message = 'GPS TRACKING ACTIVE';
      isWarning = false;
    }
    session = updated;
    distanceMeters = updated.distanceMeters;
    await store.recordPointDecision(
      updated,
      PersistedPointDecision(
        sessionId: updated.sessionId,
        sample: point,
        decision: decision,
      ),
    );
    if (kDebugMode) {
      debugPrint(
        'ORA_RUN decision=${decision.type.value} '
        'accuracyBand=${gpsQuality.name} reason=${decision.reason?.value ?? '-'}',
      );
    }
    _safeNotify();
  }

  void _showGpsWarning(String reason) {
    if (status != TrackingStatus.running &&
        status != TrackingStatus.preparingGps) {
      return;
    }
    message = reason;
    isWarning = true;
    _safeNotify();
  }

  void _tick() {
    final searchDeadline = _gpsSearchDeadlineProcessMillis;
    if (session == null &&
        status == TrackingStatus.preparingGps &&
        searchDeadline != null &&
        !gpsSearchTimedOut) {
      final remainingMillis =
          searchDeadline - _processClock.elapsedMilliseconds;
      if (remainingMillis <= 0) {
        gpsSearchRemainingSeconds = 0;
        gpsSearchTimedOut = true;
        final now = _nativeClockAnchor == null
            ? null
            : _estimatedSnapshot().monotonicMillis;
        final soak = _gpsSoakEngine.timeout(now ?? 0);
        _recordSoakState(soak.state);
        gpsSoakResult = soak;
        if (soak.state == GpsSoakState.degradedReady &&
            soak.latestSample != null) {
          _readySample = soak.latestSample;
          status = TrackingStatus.gpsReady;
          message = 'GPS READY WITH LIMITED ACCURACY - START IN OPEN AREA';
          isWarning = true;
          _gpsSearchDeadlineProcessMillis = null;
        } else {
          message = 'GPS SIGNAL IS STILL WEAK - CHOOSE HOW TO CONTINUE';
          isWarning = true;
        }
      } else {
        gpsSearchRemainingSeconds = (remainingMillis / 1000).ceil();
      }
      _safeNotify();
    }
    final current = session;
    final anchor = _nativeClockAnchor;
    if (current == null || anchor == null) return;
    final now = _estimatedSnapshot();
    activeDurationMillis = RunTimeEngine.activeDurationAt(
      current,
      now.monotonicMillis,
      now.bootEpochMillis,
    );
    sessionElapsedMillis = RunTimeEngine.sessionElapsedAt(current, now);
    averagePace = averagePaceSecondsPerKm(
      activeDurationMillis,
      distanceMeters,
      policy: policy,
    );
    if (status == TrackingStatus.running &&
        _lastRawMonotonicMillis != null &&
        now.monotonicMillis - _lastRawMonotonicMillis! >
            policy.reentryGapMillis) {
      _eventWork = _eventWork.then(
        (_) async =>
            _showGpsWarning('ACTIVE DURATION CONTINUES - WAITING FOR GPS'),
      );
    }
    if (status == TrackingStatus.running &&
        now.monotonicMillis - _lastPersistedCheckpoint >= 5000) {
      _lastPersistedCheckpoint = now.monotonicMillis;
      final checkpoint = RunTimeEngine.checkpoint(current, now);
      session = checkpoint;
      _eventWork = _eventWork.then(
        (_) => store.updateRun(
          checkpoint,
          _event(
            checkpoint.sessionId,
            'CLOCK_CHECKPOINT',
            checkpoint.status,
            checkpoint.status,
            now,
          ),
        ),
      );
    }
    _safeNotify();
  }

  void _recordSoakState(GpsSoakState state) {
    if (_lastSoakState == state) return;
    _lastSoakState = state;
    _gpsStatusChanges += 1;
  }

  Future<void> _refreshNativeState() async {
    await _takeNativeSnapshot();
    nativeStatus = await nativeAdapter.status();
    await _consumePendingNativeAction();
  }

  Future<void> _refreshNativeStatusOnly() async {
    try {
      nativeStatus = await nativeAdapter.status();
      await _consumePendingNativeAction();
      _safeNotify();
    } on Object {
      // UI state remains useful if a status refresh races service shutdown.
    }
  }

  Future<void> _consumePendingNativeAction() async {
    final action = nativeStatus?.pendingAction;
    if (action == null) return;
    await nativeAdapter.acknowledgePendingAction();
    if (action == 'pause') {
      unawaited(pause());
    } else if (action == 'resume') {
      unawaited(resume());
    } else if (action == 'finish') {
      unawaited(finish());
    }
  }

  Future<void> _enqueueCommand(Future<void> Function() operation) {
    final completer = Completer<void>();
    _commandQueue = _commandQueue.then((_) async {
      if (_disposed) {
        completer.complete();
        return;
      }
      try {
        await operation();
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<NativeClockSnapshot> _takeNativeSnapshot() async {
    final value = await nativeAdapter.snapshot();
    _nativeClockAnchor = value;
    _processAnchorMillis = _processClock.elapsedMilliseconds;
    return value;
  }

  NativeClockSnapshot _estimatedSnapshot() {
    final anchor = _nativeClockAnchor!;
    final delta = _processClock.elapsedMilliseconds - _processAnchorMillis;
    return NativeClockSnapshot(
      monotonicMillis: anchor.monotonicMillis + delta,
      epochMillis: anchor.epochMillis + delta,
      bootEpochMillis: anchor.bootEpochMillis,
    );
  }

  RunEvent _event(
    String sessionId,
    String type,
    TrackingStatus? from,
    TrackingStatus? to,
    NativeClockSnapshot now, {
    String? details,
  }) => RunEvent(
    eventId: '${sessionId}_${now.epochMillis}_${_eventSequence++}',
    sessionId: sessionId,
    type: type,
    fromStatus: from,
    toStatus: to,
    monotonicMillis: now.monotonicMillis,
    epochMillis: now.epochMillis,
    details: details,
  );

  void _applyRejectionMessage(LocationRejectReason? reason) {
    isWarning = true;
    message = switch (reason) {
      LocationRejectReason.poorAccuracy ||
      LocationRejectReason.missingAccuracy =>
        'GPS ACCURACY LOW - MOVE OUTDOORS AND VERIFY PRECISE LOCATION',
      LocationRejectReason.staleLocation =>
        'GPS FIX IS STALE - WAITING FOR A NEW FIX',
      LocationRejectReason.implausibleSpeed ||
      LocationRejectReason.continuityUnconfirmed =>
        'FILTERING UNSTABLE GPS - CONFIRMING CONTINUITY',
      _ => 'FILTERING UNSTABLE GPS SIGNAL',
    };
  }

  Future<void> _handleStartFailure(Object error) async {
    final current = session;
    final errorMessage = error is NativeTrackingFailure
        ? _messageForNativeCode(error.code, error.message)
        : 'TRACKING SERVICE COULD NOT START';
    if (current != null) {
      final now =
          _nativeClockAnchor ??
          NativeClockSnapshot(
            monotonicMillis: current.lastCheckpointMonotonicMillis,
            epochMillis: DateTime.now().millisecondsSinceEpoch,
            bootEpochMillis: current.bootEpochMillis,
          );
      final failed = current.copyWith(
        status: TrackingStatus.error,
        clearActiveAnchor: true,
        updatedAtMillis: now.epochMillis,
      );
      await store.updateRun(
        failed,
        _event(
          current.sessionId,
          'START_FAILED',
          current.status,
          TrackingStatus.error,
          now,
          details: error.runtimeType.toString(),
        ),
      );
      session = failed;
    }
    status = TrackingStatus.error;
    message = errorMessage;
    isWarning = true;
    _safeNotify();
  }

  void _failBeforeStart(String value) {
    status = TrackingStatus.idle;
    message = value;
    isWarning = true;
    _safeNotify();
  }

  void _showNativeError(Object error) {
    message = error is NativeTrackingFailure
        ? _messageForNativeCode(error.code, error.message)
        : 'TRACKING SERVICE ERROR - TRY AGAIN';
    isWarning = true;
    _safeNotify();
  }

  String _messageForNativeCode(String? code, String? fallback) =>
      switch (code) {
        'PRECISE_LOCATION_REQUIRED' =>
          'PRECISE LOCATION REQUIRED - ENABLE IT IN APP SETTINGS',
        'LOCATION_DISABLED' => 'TURN ON LOCATION SERVICES TO CONTINUE',
        'FOREGROUND_SERVICE_START_FAILED' =>
          'TRACKING SERVICE MUST BE STARTED WHILE ORA IS VISIBLE',
        'LOCATION_PERMISSION_DENIED' => 'LOCATION PERMISSION REQUIRED',
        'LOCATION_PROVIDER_UNAVAILABLE' =>
          'GPS PROVIDER UNAVAILABLE - CHECK LOCATION SETTINGS',
        _ => fallback?.toUpperCase() ?? 'TRACKING SERVICE ERROR',
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _eventWork = _eventWork.then((_) async {
        try {
          await _refreshNativeState();
          _tick();
          if (_runVisible && session == null) {
            unawaited(prepareGps());
          }
        } on Object {
          // A running foreground service may take a moment to reconnect.
        }
      });
    } else if (state == AppLifecycleState.paused && session == null) {
      unawaited(_enqueueCommand(_cancelPrepare));
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    if (session == null) unawaited(nativeAdapter.cancelPrepare());
    if (nativeAdapter case final DisposableTrackingAdapter disposable) {
      unawaited(disposable.disposeTrackingResources());
    }
    unawaited(_eventSubscription?.cancel());
    _processClock.stop();
    super.dispose();
  }
}

String formatTrackingDuration(int millis) {
  final seconds = millis < 0 ? 0 : millis ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remaining = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${remaining.toString().padLeft(2, '0')}';
}

String formatTrackingDistance(double meters) {
  final safe = meters.isFinite && meters >= 0 ? meters : 0;
  return '${(safe / 1000).toStringAsFixed(2)} KM';
}

String formatTrackingPace(int? secondsPerKm) {
  if (secondsPerKm == null || secondsPerKm <= 0) return '--:-- /KM';
  return '${(secondsPerKm ~/ 60).toString().padLeft(2, '0')}:'
      '${(secondsPerKm % 60).toString().padLeft(2, '0')} /KM';
}
