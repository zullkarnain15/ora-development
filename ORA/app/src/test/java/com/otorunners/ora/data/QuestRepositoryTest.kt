package com.otorunners.ora.data

import com.otorunners.ora.backend.BackendLoginResult
import com.otorunners.ora.backend.BackendParticipant
import com.otorunners.ora.backend.OraBackendApi
import com.otorunners.ora.backend.SubmitActivityStatus
import com.otorunners.ora.data.local.ActivityEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class QuestRepositoryTest {
    @Test
    fun fetchActiveQuests_returnsBackendQuestMaster() = runBlocking {
        val quests = listOf(quest())
        val repository = QuestRepository(QuestFakeBackend(quests), Dispatchers.Unconfined)

        assertEquals(quests, repository.fetchActiveQuests())
    }

    @Test
    fun fetchQuestsWithProgress_usesSessionProgressEndpoint() = runBlocking {
        val progressQuest = quest().copy(
            progress = 10.0,
            progressPercent = 50.0,
            status = "IN_PROGRESS"
        )
        val backend = QuestFakeBackend(
            quests = listOf(quest()),
            progressQuests = listOf(progressQuest)
        )
        val repository = QuestRepository(backend, Dispatchers.Unconfined)

        val actual = repository.fetchQuestsWithProgress("session-token")

        assertEquals(listOf(progressQuest), actual)
        assertEquals("session-token", backend.receivedProgressToken)
    }

    @Test
    fun fetchQuestsWithProgress_fallsBackToMasterWhenProgressFails() = runBlocking {
        val masterQuests = listOf(quest())
        val backend = QuestFakeBackend(masterQuests, progressFails = true)
        val repository = QuestRepository(backend, Dispatchers.Unconfined)

        assertEquals(masterQuests, repository.fetchQuestsWithProgress("expired-token"))
    }

    @Test
    fun claimReward_forwardsSessionAndQuestId() = runBlocking {
        val expected = QuestClaimResult(
            questId = "DEV-Q001",
            rewardXp = 100,
            status = "CLAIMED",
            claimId = "claim-1",
            claimedAt = "2026-08-13T03:00:00.000Z"
        )
        val backend = QuestFakeBackend(listOf(quest()), claimResult = expected)
        val repository = QuestRepository(backend, Dispatchers.Unconfined)

        assertEquals(expected, repository.claimReward("session-token", "DEV-Q001"))
        assertEquals("session-token", backend.receivedClaimToken)
        assertEquals("DEV-Q001", backend.receivedClaimQuestId)
    }

    private fun quest() = QuestMaster(
        questId = "DEV-Q001",
        questName = "20 KM WEEKLY TRAIL",
        questType = "DISTANCE",
        targetValue = 20.0,
        unit = "KM",
        rewardXp = 100,
        periodType = "WEEKLY",
        startDate = "2026-08-10",
        endDate = "2026-08-16"
    )
}

private class QuestFakeBackend(
    private val quests: List<QuestMaster>,
    private val progressQuests: List<QuestMaster> = quests,
    private val progressFails: Boolean = false,
    private val claimResult: QuestClaimResult? = null
) : OraBackendApi {
    var receivedProgressToken: String? = null
    var receivedClaimToken: String? = null
    var receivedClaimQuestId: String? = null

    override fun getQuests(): List<QuestMaster> = quests
    override fun getQuestProgress(sessionToken: String): List<QuestMaster> {
        receivedProgressToken = sessionToken
        if (progressFails) error("Progress unavailable")
        return progressQuests
    }

    override fun claimQuestReward(sessionToken: String, questId: String): QuestClaimResult {
        receivedClaimToken = sessionToken
        receivedClaimQuestId = questId
        return claimResult ?: error("Claim result missing")
    }

    override fun login(nik: String, pin: String): BackendLoginResult = error("Not used")
    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant = error("Not used")
    override fun submitActivity(sessionToken: String, activity: ActivityEntity): SubmitActivityStatus = error("Not used")
    override fun getUserStats(sessionToken: String): UserStats = error("Not used")
}
