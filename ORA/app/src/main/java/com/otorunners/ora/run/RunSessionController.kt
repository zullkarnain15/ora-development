package com.otorunners.ora.run

import android.content.Context
import android.location.Location
import android.os.SystemClock
import com.otorunners.ora.auth.UserSession
import com.otorunners.ora.data.ActivityRepository
import com.otorunners.ora.data.ActivitySaveResult
import com.otorunners.ora.data.ActivitySyncManager
import com.otorunners.ora.data.FinishedRunActivity
import com.otorunners.ora.data.local.OraDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class RunAutoSyncEvent(
    val ownerNik: String,
    val syncedCount: Int,
    val pendingCount: Int,
    val failedCount: Int
)

object RunSessionController {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _uiState = MutableStateFlow(RunSessionUiState())
    private val _autoSyncEvents = MutableSharedFlow<RunAutoSyncEvent>(extraBufferCapacity = 8)
    private val locationEngine = RunLocationEngine()
    private val distanceResult = FloatArray(1)

    val uiState: StateFlow<RunSessionUiState> = _uiState.asStateFlow()
    val autoSyncEvents: SharedFlow<RunAutoSyncEvent> = _autoSyncEvents.asSharedFlow()

    private var tracker: RunTracker? = null
    private var activityRepository: ActivityRepository? = null
    private var activitySyncManager: ActivitySyncManager? = null
    private var currentUser: UserSession? = null
    private var runOwner: UserSession? = null
    private var runStartedAtEpochMillis = 0L
    private var activeStartedAtMillis = 0L
    private var accumulatedActiveMillis = 0L
    private var gpsAcquisitionStartedAtMillis = 0L
    private var timerJob: Job? = null

    fun configure(context: Context) {
        RunDiagnostics.configure()
        if (activityRepository == null) {
            val activityDao = OraDatabase.getInstance(context.applicationContext).activityDao()
            activityRepository = ActivityRepository(
                activityDao = activityDao
            )
            activitySyncManager = ActivitySyncManager(activityDao = activityDao)
        }
        if (tracker != null) return

        tracker = RunTracker(
            context = context.applicationContext,
            onLocation = ::handleLocation,
            onLocationUnavailable = ::handleLocationUnavailable,
            onTrackingError = ::handleTrackingError
        )
    }

    fun setActiveUser(user: UserSession) {
        currentUser = user
    }

    fun clearActiveUser() {
        currentUser = null
        runOwner = null
    }

    fun startAdventure(context: Context) {
        configure(context)
        if (_uiState.value.status == RunStatus.TRACKING) return

        tracker?.stop()
        timerJob?.cancel()
        accumulatedActiveMillis = 0L
        activeStartedAtMillis = 0L
        gpsAcquisitionStartedAtMillis = SystemClock.elapsedRealtime()
        runStartedAtEpochMillis = System.currentTimeMillis()
        runOwner = currentUser
        locationEngine.startNewSession()

        _uiState.value = RunSessionUiState(
            status = RunStatus.TRACKING,
            message = "ACQUIRING GPS",
            isBackgroundTracking = true
        )
        RunDiagnostics.debug { "START | timer waiting for first acceptable GPS baseline" }
        tracker?.start()
    }

    fun pauseAdventure() {
        if (_uiState.value.status != RunStatus.TRACKING) return

        accumulatedActiveMillis = currentActiveDurationMillis()
        activeStartedAtMillis = 0L
        gpsAcquisitionStartedAtMillis = 0L
        timerJob?.cancel()
        tracker?.stop()
        locationEngine.pause()
        publishState(
            status = RunStatus.PAUSED,
            durationMillis = accumulatedActiveMillis,
            message = "Adventure paused"
        )
        RunDiagnostics.debug { "PAUSE | ${diagnosticSnapshot()}" }
    }

    fun resumeAdventure(context: Context) {
        configure(context)
        if (_uiState.value.status != RunStatus.PAUSED) return

        activeStartedAtMillis = 0L
        gpsAcquisitionStartedAtMillis = SystemClock.elapsedRealtime()
        locationEngine.resume()
        publishState(
            status = RunStatus.TRACKING,
            durationMillis = accumulatedActiveMillis,
            message = "ACQUIRING GPS"
        )
        RunDiagnostics.debug { "RESUME | timer waiting for a new GPS baseline" }
        tracker?.start()
    }

    fun finishAdventure() {
        val currentStatus = _uiState.value.status
        if (currentStatus != RunStatus.TRACKING && currentStatus != RunStatus.PAUSED) return

        val endDateTimeMillis = System.currentTimeMillis()
        val finalDuration = if (currentStatus == RunStatus.TRACKING) {
            currentActiveDurationMillis()
        } else {
            accumulatedActiveMillis
        }
        val finalDistance = locationEngine.totalDistanceMeters
        val finalPaceSecondsPerKm = averagePaceSecondsPerKm(finalDuration, finalDistance)
        val startDateTimeMillis = runStartedAtEpochMillis.takeIf { it > 0L } ?: endDateTimeMillis

        accumulatedActiveMillis = finalDuration
        activeStartedAtMillis = 0L
        gpsAcquisitionStartedAtMillis = 0L
        timerJob?.cancel()
        tracker?.stop()
        locationEngine.stop()

        _uiState.value = RunSessionUiState(
            status = RunStatus.FINISHED,
            distanceMeters = finalDistance,
            activeDurationMillis = finalDuration,
            message = "Adventure complete",
            isBackgroundTracking = false,
            debugInfo = locationEngine.diagnostics,
            summary = RunSummary(
                distanceMeters = finalDistance,
                durationMillis = finalDuration,
                startDateTimeMillis = startDateTimeMillis,
                endDateTimeMillis = endDateTimeMillis,
                averagePaceSecondsPerKm = finalPaceSecondsPerKm,
                saveStatus = ActivitySaveStatus.SAVING,
                saveMessage = "SAVING ADVENTURE"
            )
        )
        RunDiagnostics.debug { "FINISH | ${diagnosticSnapshot(finalDuration)}" }
        saveFinishedActivity(
            owner = runOwner,
            startDateTimeMillis = startDateTimeMillis,
            endDateTimeMillis = endDateTimeMillis,
            distanceMeters = finalDistance,
            durationMillis = finalDuration,
            averagePaceSecondsPerKm = finalPaceSecondsPerKm
        )
    }

    fun doneSummary() {
        tracker?.stop()
        timerJob?.cancel()
        accumulatedActiveMillis = 0L
        activeStartedAtMillis = 0L
        gpsAcquisitionStartedAtMillis = 0L
        runStartedAtEpochMillis = 0L
        runOwner = null
        locationEngine.reset()
        _uiState.value = RunSessionUiState()
    }

    fun reportPermissionDenied() {
        _uiState.value = _uiState.value.copy(
            message = "Location permission is required to start an adventure.",
            isWarning = true
        )
    }

    fun reportPreciseLocationRequired() {
        _uiState.value = _uiState.value.copy(
            message = "Precise location is required for accurate tracking.",
            isWarning = true
        )
    }

    fun reportNotificationPermissionRequired() {
        _uiState.value = _uiState.value.copy(
            message = "Notification permission is required for background tracking.",
            isWarning = true
        )
    }

    private fun startTimer() {
        timerJob?.cancel()
        timerJob = scope.launch {
            while (_uiState.value.status == RunStatus.TRACKING) {
                publishState(
                    status = RunStatus.TRACKING,
                    durationMillis = currentActiveDurationMillis(),
                    message = _uiState.value.message,
                    isWarning = _uiState.value.isWarning
                )
                delay(1_000L)
            }
        }
    }

    private fun handleLocation(location: Location) {
        if (_uiState.value.status != RunStatus.TRACKING) {
            RunDiagnostics.debug { "IGNORE point | reason=session is not tracking" }
            return
        }

        val point = GpsPoint(
            latitude = location.latitude,
            longitude = location.longitude,
            accuracyMeters = location.accuracy.takeIf { location.hasAccuracy() },
            elapsedRealtimeNanos = location.elapsedRealtimeNanos
        )
        val decision = locationEngine.process(
            point = point,
            nowElapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos(),
            distanceBetweenMeters = ::distanceBetweenMeters
        )

        when (decision.type) {
            LocationDecisionType.BASELINE -> {
                activeStartedAtMillis = maxOf(
                    point.elapsedRealtimeNanos / NANOS_PER_MILLISECOND,
                    gpsAcquisitionStartedAtMillis
                )
                gpsAcquisitionStartedAtMillis = 0L
                startTimer()
                publishTrackingState("GPS tracking active")
            }
            LocationDecisionType.REENTRY_BASELINE -> {
                publishTrackingState("GPS signal restored")
            }
            LocationDecisionType.ACCEPTED -> {
                publishTrackingState("GPS tracking active")
            }
            LocationDecisionType.REJECTED -> publishRejectedState(decision)
            LocationDecisionType.IGNORED -> Unit
        }

        logDecision(point, decision)
    }

    private fun publishRejectedState(decision: LocationDecision) {
        when (decision.reason) {
            LocationRejectReason.MISSING_ACCURACY,
            LocationRejectReason.POOR_ACCURACY -> publishTrackingState(
                message = "GPS accuracy is low",
                isWarning = true
            )
            LocationRejectReason.DUPLICATE_COORDINATE,
            LocationRejectReason.JITTER -> publishTrackingState("GPS tracking active")
            else -> publishTrackingState(
                message = "Filtering unstable GPS signal",
                isWarning = true
            )
        }
    }

    private fun publishTrackingState(message: String, isWarning: Boolean = false) {
        publishState(
            status = RunStatus.TRACKING,
            durationMillis = currentActiveDurationMillis(),
            message = message,
            isWarning = isWarning
        )
    }

    private fun logDecision(point: GpsPoint, decision: LocationDecision) {
        val result = when (decision.type) {
            LocationDecisionType.BASELINE -> "ACCEPT baseline"
            LocationDecisionType.REENTRY_BASELINE -> "ACCEPT re-entry baseline"
            LocationDecisionType.ACCEPTED -> "ACCEPT point"
            LocationDecisionType.REJECTED -> "REJECT point | reason=${decision.reason?.diagnosticText}"
            LocationDecisionType.IGNORED -> "IGNORE point | reason=${decision.reason?.diagnosticText}"
        }
        RunDiagnostics.debug {
            "$result | accuracy=${formatDecimal(point.accuracyMeters)} m | " +
                "segment=${formatDecimal(decision.segmentMeters)} m | " +
                "speed=${formatDecimal(decision.impliedSpeedMetersPerSecond)} m/s | " +
                diagnosticSnapshot()
        }
    }

    private fun diagnosticSnapshot(durationMillis: Long = currentActiveDurationMillis()): String {
        val info = locationEngine.diagnostics
        return "elapsed=$durationMillis ms | " +
            "distance=${formatDecimal(locationEngine.totalDistanceMeters)} m | " +
            "accepted=${info.acceptedPointsCount} | rejected=${info.rejectedPointsCount} | " +
            "avgPace=${formatAveragePace(durationMillis, locationEngine.totalDistanceMeters)}"
    }

    private fun formatDecimal(value: Float?): String {
        return value?.takeIf { it.isFinite() }
            ?.let { "%.1f".format(java.util.Locale.US, it) }
            ?: "unknown"
    }

    private fun distanceBetweenMeters(from: GpsPoint, to: GpsPoint): Float {
        Location.distanceBetween(
            from.latitude,
            from.longitude,
            to.latitude,
            to.longitude,
            distanceResult
        )
        return distanceResult[0]
    }

    private fun handleLocationUnavailable() {
        if (_uiState.value.status == RunStatus.TRACKING) {
            publishState(
                status = RunStatus.TRACKING,
                durationMillis = currentActiveDurationMillis(),
                message = "GPS signal lost - waiting for fix",
                isWarning = true
            )
            RunDiagnostics.debug { "GPS UNAVAILABLE | ${diagnosticSnapshot()}" }
        }
    }

    private fun handleTrackingError(message: String) {
        if (_uiState.value.status == RunStatus.TRACKING) {
            accumulatedActiveMillis = currentActiveDurationMillis()
        }
        activeStartedAtMillis = 0L
        gpsAcquisitionStartedAtMillis = 0L
        runStartedAtEpochMillis = 0L
        timerJob?.cancel()
        tracker?.stop()
        locationEngine.stop()
        _uiState.value = _uiState.value.copy(
            status = RunStatus.IDLE,
            distanceMeters = locationEngine.totalDistanceMeters,
            activeDurationMillis = accumulatedActiveMillis,
            message = message,
            isWarning = true,
            isBackgroundTracking = false,
            debugInfo = locationEngine.diagnostics
        )
        RunDiagnostics.debug { "TRACKING ERROR | message=$message | ${diagnosticSnapshot()}" }
    }

    private fun saveFinishedActivity(
        owner: UserSession?,
        startDateTimeMillis: Long,
        endDateTimeMillis: Long,
        distanceMeters: Float,
        durationMillis: Long,
        averagePaceSecondsPerKm: Int?
    ) {
        val repository = activityRepository
        if (owner == null || repository == null) {
            publishSaveResult(
                startDateTimeMillis = startDateTimeMillis,
                saveStatus = ActivitySaveStatus.FAILED,
                saveMessage = "ADVENTURE SAVE FAILED"
            )
            RunDiagnostics.debug { "SAVE FAILED | reason=missing owner or repository" }
            return
        }

        scope.launch {
            try {
                val result = repository.saveFinishedActivity(
                    FinishedRunActivity(
                        ownerNik = owner.nik,
                        nicknameSnapshot = owner.nickname,
                        divisionGuildSnapshot = owner.divisionGuild,
                        startDateTimeMillis = startDateTimeMillis,
                        endDateTimeMillis = endDateTimeMillis,
                        distanceMeters = distanceMeters,
                        activeDurationMillis = durationMillis,
                        averagePaceSecondsPerKm = averagePaceSecondsPerKm
                    )
                )
                when (result) {
                    is ActivitySaveResult.Saved -> {
                        publishSaveResult(
                            startDateTimeMillis = startDateTimeMillis,
                            saveStatus = ActivitySaveStatus.SAVED,
                            saveMessage = "ADVENTURE SAVED",
                            activityId = result.activity.activityId
                        )
                        RunDiagnostics.debug { "SAVE OK | activityId=${result.activity.activityId} | owner=${owner.nik}" }
                        syncSavedActivities(owner)
                    }
                    is ActivitySaveResult.Duplicate -> {
                        publishSaveResult(
                            startDateTimeMillis = startDateTimeMillis,
                            saveStatus = ActivitySaveStatus.SAVED,
                            saveMessage = "ADVENTURE ALREADY SAVED",
                            activityId = result.activityId
                        )
                        RunDiagnostics.debug { "SAVE DUPLICATE | activityId=${result.activityId} | owner=${owner.nik}" }
                    }
                }
            } catch (error: Exception) {
                publishSaveResult(
                    startDateTimeMillis = startDateTimeMillis,
                    saveStatus = ActivitySaveStatus.FAILED,
                    saveMessage = "ADVENTURE SAVE FAILED"
                )
                RunDiagnostics.debug { "SAVE FAILED | ${error.javaClass.simpleName}: ${error.message}" }
            }
        }
    }

    private suspend fun syncSavedActivities(owner: UserSession) {
        try {
            val result = activitySyncManager?.syncPending(owner) ?: return
            _autoSyncEvents.emit(
                RunAutoSyncEvent(
                    ownerNik = owner.nik,
                    syncedCount = result.syncedCount,
                    pendingCount = result.pendingCount,
                    failedCount = result.failedCount
                )
            )
            RunDiagnostics.debug {
                "SYNC COMPLETE | owner=${owner.nik} | synced=${result.syncedCount} | pending=${result.pendingCount}"
            }
        } catch (error: Exception) {
            RunDiagnostics.debug { "SYNC FAILED | owner=${owner.nik} | ${error.javaClass.simpleName}: ${error.message}" }
        }
    }

    private fun publishSaveResult(
        startDateTimeMillis: Long,
        saveStatus: ActivitySaveStatus,
        saveMessage: String,
        activityId: String? = null
    ) {
        val current = _uiState.value
        val summary = current.summary ?: return
        if (current.status != RunStatus.FINISHED || summary.startDateTimeMillis != startDateTimeMillis) return

        _uiState.value = current.copy(
            message = saveMessage,
            isWarning = saveStatus == ActivitySaveStatus.FAILED,
            summary = summary.copy(
                activityId = activityId ?: summary.activityId,
                saveStatus = saveStatus,
                saveMessage = saveMessage
            )
        )
    }

    private fun currentActiveDurationMillis(): Long {
        return accumulatedActiveMillis + if (activeStartedAtMillis > 0L) {
            (SystemClock.elapsedRealtime() - activeStartedAtMillis).coerceAtLeast(0L)
        } else {
            0L
        }
    }

    private fun publishState(
        status: RunStatus,
        durationMillis: Long,
        message: String,
        isWarning: Boolean = false
    ) {
        _uiState.value = _uiState.value.copy(
            status = status,
            distanceMeters = locationEngine.totalDistanceMeters,
            activeDurationMillis = durationMillis,
            message = message,
            isWarning = isWarning,
            isBackgroundTracking = status == RunStatus.TRACKING || status == RunStatus.PAUSED,
            debugInfo = locationEngine.diagnostics
        )
    }

    private const val NANOS_PER_MILLISECOND = 1_000_000L
}
