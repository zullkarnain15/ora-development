package com.otorunners.ora.data

data class QuestMaster(
    val questId: String,
    val questName: String,
    val questType: String,
    val targetValue: Double,
    val unit: String,
    val rewardXp: Int,
    val periodType: String,
    val startDate: String,
    val endDate: String,
    val progress: Double? = null,
    val progressPercent: Double? = null,
    val status: String? = null,
    val completed: Boolean = false,
    val claimable: Boolean? = null,
    val claimBlockedReason: String? = null,
    val claimed: Boolean = false,
    val claimId: String? = null,
    val claimedAt: String? = null
)

data class QuestClaimResult(
    val questId: String,
    val rewardXp: Int,
    val status: String,
    val claimId: String?,
    val claimedAt: String?
)

data class QuestUiState(
    val quests: List<QuestMaster> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val claimingQuestId: String? = null,
    val claimMessageQuestId: String? = null,
    val claimMessage: String? = null
)
