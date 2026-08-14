package com.otorunners.ora.data

data class UserStats(
    val nik: String,
    val nickname: String,
    val division: String,
    val totalActivities: Int,
    val totalDistanceKm: Double,
    val totalDurationSec: Double,
    val totalXp: Int,
    val currentLevel: Int,
    val currentLevelName: String,
    val nextLevelXp: Int?,
    val lastActivityId: String,
    val lastActivityAt: String,
    val updatedAt: String?
)

data class UserStatsUiState(
    val stats: UserStats? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)
