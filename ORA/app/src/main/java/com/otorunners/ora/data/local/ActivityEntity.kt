package com.otorunners.ora.data.local

const val SYNC_STATUS_LOCAL_ONLY = "LOCAL_ONLY"
const val SYNC_STATUS_PENDING = "PENDING"
const val SYNC_STATUS_SYNCED = "SYNCED"

data class ActivityEntity(
    val activityId: String,
    val ownerNik: String,
    val nicknameSnapshot: String?,
    val divisionGuildSnapshot: String?,
    val startDateTimeMillis: Long,
    val endDateTimeMillis: Long,
    val distanceMeters: Float,
    val activeDurationMillis: Long,
    val averagePaceSecondsPerKm: Int?,
    val createdAtMillis: Long,
    val syncStatus: String = SYNC_STATUS_PENDING
)

data class ActivityTotals(
    val activityCount: Int,
    val totalDistanceMeters: Double,
    val totalActiveDurationMillis: Long
)
