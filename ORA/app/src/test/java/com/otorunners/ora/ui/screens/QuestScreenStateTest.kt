package com.otorunners.ora.ui.screens

import com.otorunners.ora.data.QuestMaster
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuestScreenStateTest {
    @Test
    fun zeroProgress_isNotStartedWithoutClaim() {
        val quest = quest(progress = 0.0)

        assertEquals("NOT STARTED", quest.questStatusLabel())
        assertEquals(QuestVisualState.NOT_STARTED, quest.questVisualState())
        assertFalse(quest.canClaimReward())
    }

    @Test
    fun partialProgress_isInProgressWithoutClaim() {
        val quest = quest(progress = 2.0)

        assertEquals("IN PROGRESS", quest.questStatusLabel())
        assertEquals(QuestVisualState.IN_PROGRESS, quest.questVisualState())
        assertEquals(0.4f, quest.visualProgress(quest.questVisualState()))
        assertFalse(quest.canClaimReward())
    }

    @Test
    fun completedQuest_canBeClaimed() {
        val quest = quest(progress = 5.0, completed = true, status = "COMPLETED")

        assertEquals("QUEST COMPLETE", quest.questStatusLabel())
        assertEquals(QuestVisualState.CLAIMABLE, quest.questVisualState())
        assertEquals("Reward ready: +100 XP", quest.rewardStateText(quest.questVisualState()))
        assertEquals(1f, quest.visualProgress(quest.questVisualState()))
        assertTrue(quest.canClaimReward())
    }

    @Test
    fun claimedQuest_hasNoActiveClaimButton() {
        val quest = quest(
            progress = 5.0,
            completed = true,
            claimed = true,
            status = "COMPLETED"
        )

        assertEquals("CLAIMED", quest.questStatusLabel())
        assertEquals(QuestVisualState.CLAIMED, quest.questVisualState())
        assertEquals("Reward collected: +100 XP", quest.rewardStateText(quest.questVisualState()))
        assertEquals(1f, quest.visualProgress(quest.questVisualState()))
        assertFalse(quest.canClaimReward())
    }

    @Test
    fun guildAndUnknownTypes_cannotBeClaimed() {
        val guild = quest(
            progress = 0.0,
            completed = false,
            status = "UNSUPPORTED_GROUP_SCOPE"
        )
        val unknown = quest(
            progress = 5.0,
            completed = true,
            status = "UNKNOWN_TYPE"
        )

        assertEquals("GUILD QUEST COMING SOON", guild.questStatusLabel())
        assertEquals(QuestVisualState.UNSUPPORTED, guild.questVisualState())
        assertEquals(0f, guild.visualProgress(guild.questVisualState()))
        assertFalse(guild.canClaimReward())
        assertEquals("UNKNOWN TYPE", unknown.questStatusLabel())
        assertEquals(QuestVisualState.UNKNOWN, unknown.questVisualState())
        assertFalse(unknown.canClaimReward())
    }

    @Test
    fun completedGuildQuest_usesCompleteVisualButBlocksRewardClaim() {
        val guild = quest(
            progress = 5.0,
            completed = true,
            status = "COMPLETED"
        ).copy(
            questType = "GUILD_DISTANCE",
            claimable = false,
            claimBlockedReason = "GUILD_REWARD_NOT_READY"
        )

        assertEquals(QuestVisualState.CLAIMABLE, guild.questVisualState())
        assertEquals("GUILD REWARD COMING SOON", guild.rewardStateText(guild.questVisualState()))
        assertEquals(1f, guild.visualProgress(guild.questVisualState()))
        assertFalse(guild.canClaimReward())
    }

    @Test
    fun guildQuestWithoutDivision_isSafeNoGuildState() {
        val guild = quest(progress = 0.0, status = "NO_GUILD").copy(
            questType = "GUILD_DISTANCE",
            claimable = false,
            claimBlockedReason = "GUILD_REWARD_NOT_READY"
        )

        assertEquals(QuestVisualState.NO_GUILD, guild.questVisualState())
        assertEquals("NO GUILD ASSIGNED", guild.questStatusLabel())
        assertFalse(guild.canClaimReward())
    }

    @Test
    fun fallbackMasterQuest_staysNeutralAndCannotClaim() {
        val fallback = quest(progress = 0.0).copy(progress = null, status = null)

        assertEquals(QuestVisualState.NOT_STARTED, fallback.questVisualState())
        assertFalse(fallback.canClaimReward())
    }

    private fun quest(
        progress: Double,
        completed: Boolean = false,
        claimed: Boolean = false,
        status: String = if (progress > 0.0) "IN_PROGRESS" else "NOT_STARTED"
    ) = QuestMaster(
        questId = "Q1",
        questName = "TEST QUEST",
        questType = "DISTANCE",
        targetValue = 5.0,
        unit = "KM",
        rewardXp = 100,
        periodType = "WEEKLY",
        startDate = "2026-08-10",
        endDate = "2026-08-16",
        progress = progress,
        progressPercent = (progress / 5.0 * 100.0).coerceAtMost(100.0),
        status = status,
        completed = completed,
        claimed = claimed
    )
}
