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

class UserStatsRepositoryTest {
    @Test
    fun fetch_returnsStatsForBackendSession() = runBlocking {
        val expected = UserStats(
            nik = "10000004",
            nickname = "TRAIL04",
            division = "Operations",
            totalActivities = 1,
            totalDistanceKm = 1.25,
            totalDurationSec = 600.0,
            totalXp = 13,
            currentLevel = 1,
            currentLevelName = "ROOKIE SCOUT",
            nextLevelXp = 100,
            lastActivityId = "activity-1",
            lastActivityAt = "2026-08-12T07:10:00+07:00",
            updatedAt = "2026-08-12T12:12:37.053Z"
        )
        val backend = UserStatsFakeBackend(expected)
        val repository = UserStatsRepository(backend, Dispatchers.Unconfined)

        val actual = repository.fetch("session-token")

        assertEquals(expected, actual)
        assertEquals("session-token", backend.receivedToken)
    }
}

private class UserStatsFakeBackend(
    private val stats: UserStats
) : OraBackendApi {
    var receivedToken: String? = null

    override fun getUserStats(sessionToken: String): UserStats {
        receivedToken = sessionToken
        return stats
    }

    override fun login(nik: String, pin: String): BackendLoginResult = error("Not used")
    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant = error("Not used")
    override fun submitActivity(sessionToken: String, activity: ActivityEntity): SubmitActivityStatus = error("Not used")
    override fun getQuests(): List<QuestMaster> = error("Not used")
}
