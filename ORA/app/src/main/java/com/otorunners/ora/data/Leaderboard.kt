package com.otorunners.ora.data

enum class LeaderboardScope(val apiValue: String, val label: String) {
    GLOBAL("GLOBAL", "GLOBAL"),
    GUILD("GUILD", "GUILD")
}

enum class LeaderboardMetric(val apiValue: String, val label: String) {
    TOTAL_XP("TOTAL_XP", "XP"),
    TOTAL_DISTANCE("TOTAL_DISTANCE", "DISTANCE"),
    TOTAL_ACTIVITIES("TOTAL_ACTIVITIES", "RUNS")
}

data class LeaderboardEntry(
    val rank: Int,
    val nik: String,
    val nickname: String,
    val division: String,
    val totalXp: Int,
    val totalDistanceKm: Double,
    val totalActivities: Int,
    val currentLevel: Int,
    val currentLevelName: String
)

data class CurrentUserRank(
    val rank: Int,
    val metricValue: Double
)

data class LeaderboardResponse(
    val scope: LeaderboardScope,
    val status: String,
    val metric: LeaderboardMetric,
    val leaderboard: List<LeaderboardEntry>,
    val currentUserRank: CurrentUserRank?
)

data class LeaderboardUiState(
    val ownerNik: String? = null,
    val scope: LeaderboardScope = LeaderboardScope.GLOBAL,
    val metric: LeaderboardMetric = LeaderboardMetric.TOTAL_XP,
    val status: String? = null,
    val entries: List<LeaderboardEntry> = emptyList(),
    val currentUserRank: CurrentUserRank? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)
