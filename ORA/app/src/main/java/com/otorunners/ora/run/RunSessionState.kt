package com.otorunners.ora.run

enum class RunStatus {
    IDLE,
    TRACKING,
    PAUSED,
    FINISHED
}

enum class ActivitySaveStatus {
    NOT_SAVED,
    SAVING,
    SAVED,
    FAILED
}

data class RunSummary(
    val distanceMeters: Float,
    val durationMillis: Long,
    val startDateTimeMillis: Long,
    val endDateTimeMillis: Long,
    val averagePaceSecondsPerKm: Int?,
    val activityId: String? = null,
    val saveStatus: ActivitySaveStatus = ActivitySaveStatus.NOT_SAVED,
    val saveMessage: String? = null
)

data class RunSessionUiState(
    val status: RunStatus = RunStatus.IDLE,
    val distanceMeters: Float = 0f,
    val activeDurationMillis: Long = 0L,
    val message: String = "GPS READY",
    val isWarning: Boolean = false,
    val isBackgroundTracking: Boolean = false,
    val debugInfo: RunLocationDiagnostics = RunLocationDiagnostics(),
    val summary: RunSummary? = null
)
