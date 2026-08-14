package com.otorunners.ora.run

import android.app.Application
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import com.otorunners.ora.auth.UserSession
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.roundToInt

class RunViewModel(application: Application) : AndroidViewModel(application) {
    val uiState: StateFlow<RunSessionUiState> = RunSessionController.uiState
    val autoSyncEvents = RunSessionController.autoSyncEvents

    init {
        RunSessionController.configure(application)
    }

    fun startAdventure() {
        sendServiceCommand(RunTrackingService.ACTION_START)
    }

    fun setActiveUser(user: UserSession) {
        RunSessionController.setActiveUser(user)
    }

    fun clearActiveUser() {
        RunSessionController.clearActiveUser()
    }

    fun pauseAdventure() {
        sendServiceCommand(RunTrackingService.ACTION_PAUSE)
    }

    fun resumeAdventure() {
        sendServiceCommand(RunTrackingService.ACTION_RESUME)
    }

    fun finishAdventure() {
        sendServiceCommand(RunTrackingService.ACTION_FINISH)
    }

    fun doneSummary() {
        sendServiceCommand(RunTrackingService.ACTION_STOP_AND_RESET)
    }

    fun reportPermissionDenied() {
        RunSessionController.reportPermissionDenied()
    }

    fun reportPreciseLocationRequired() {
        RunSessionController.reportPreciseLocationRequired()
    }

    fun reportNotificationPermissionRequired() {
        RunSessionController.reportNotificationPermissionRequired()
    }

    fun pauseForBackground() {
        // RUN Engine v2 keeps tracking in the foreground service while ORA is backgrounded.
    }

    private fun sendServiceCommand(action: String) {
        val context = getApplication<Application>()
        val intent = Intent(context, RunTrackingService::class.java).setAction(action)
        if (action == RunTrackingService.ACTION_START) {
            ContextCompat.startForegroundService(context, intent)
        } else {
            context.startService(intent)
        }
    }
}

fun formatDistanceKm(distanceMeters: Float): String {
    val safeDistance = distanceMeters.takeIf { it.isFinite() && it >= 0f } ?: 0f
    return "%.2f KM".format(safeDistance / 1_000f)
}

fun formatDuration(durationMillis: Long): String {
    val totalSeconds = durationMillis / 1_000L
    val hours = totalSeconds / 3_600L
    val minutes = (totalSeconds % 3_600L) / 60L
    val seconds = totalSeconds % 60L
    return "%02d:%02d:%02d".format(hours, minutes, seconds)
}

fun formatAveragePace(durationMillis: Long, distanceMeters: Float): String {
    val paceSecondsPerKm = averagePaceSecondsPerKm(durationMillis, distanceMeters) ?: return "--:-- /KM"
    return formatPaceSecondsPerKm(paceSecondsPerKm)
}

fun formatPaceSecondsPerKm(paceSecondsPerKm: Int?): String {
    val safePace = paceSecondsPerKm?.takeIf { it > 0 } ?: return "--:-- /KM"
    val minutes = safePace / 60
    val seconds = safePace % 60
    return "%02d:%02d /KM".format(minutes, seconds)
}

fun averagePaceSecondsPerKm(durationMillis: Long, distanceMeters: Float): Int? {
    if (!distanceMeters.isFinite() ||
        distanceMeters < RunTrackingConfig.MIN_PACE_DISTANCE_METERS ||
        durationMillis <= 0L
    ) {
        return null
    }

    val durationSeconds = durationMillis.toDouble() / 1_000.0
    val distanceKilometers = distanceMeters.toDouble() / 1_000.0
    val pace = durationSeconds / distanceKilometers
    if (!pace.isFinite() || pace <= 0.0) return null

    return pace.roundToInt()
}
