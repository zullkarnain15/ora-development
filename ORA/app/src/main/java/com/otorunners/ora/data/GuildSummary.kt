package com.otorunners.ora.data

data class GuildSummary(
    val guildId: String,
    val guildName: String,
    val memberCount: Int,
    val activeMemberCount: Int,
    val totalDistanceKm: Double,
    val totalActivities: Int,
    val totalXp: Int,
    val currentLevel: Int = 1,
    val currentLevelName: String = "",
    val displayName: String = "",
    val description: String = ""
)

data class GuildMember(
    val nik: String,
    val nickname: String,
    val division: String,
    val totalDistanceKm: Double,
    val totalActivities: Int,
    val totalXp: Int,
    val currentLevel: Int,
    val currentLevelName: String
)

data class GuildSummaryResponse(
    val status: String,
    val guild: GuildSummary?,
    val members: List<GuildMember>
)

data class GuildDirectoryResponse(
    val guilds: List<GuildSummary>
)

data class GuildUiState(
    val ownerNik: String? = null,
    val status: String? = null,
    val guild: GuildSummary? = null,
    val members: List<GuildMember> = emptyList(),
    val guilds: List<GuildSummary> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val isGuildDirectoryLoading: Boolean = false,
    val guildDirectoryErrorMessage: String? = null
)
