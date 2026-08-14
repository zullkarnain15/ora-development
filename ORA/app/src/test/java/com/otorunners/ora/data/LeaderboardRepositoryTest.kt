package com.otorunners.ora.data

import com.otorunners.ora.backend.BackendLoginResult
import com.otorunners.ora.backend.BackendParticipant
import com.otorunners.ora.backend.OraBackendApi
import com.otorunners.ora.backend.SubmitActivityStatus
import com.otorunners.ora.data.local.ActivityEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LeaderboardRepositoryTest {
    @Test
    fun fetchLeaderboard_forwardsSessionAndMetric() = runBlocking {
        val expected = response(LeaderboardMetric.TOTAL_DISTANCE)
        val backend = LeaderboardFakeBackend(expected)
        val repository = LeaderboardRepository(backend, Dispatchers.Unconfined)

        assertEquals(
            expected,
            repository.fetchLeaderboard(
                "session-token",
                LeaderboardScope.GUILD,
                LeaderboardMetric.TOTAL_DISTANCE
            )
        )
        assertEquals("session-token", backend.receivedSessionToken)
        assertEquals(LeaderboardScope.GUILD, backend.receivedScope)
        assertEquals(LeaderboardMetric.TOTAL_DISTANCE, backend.receivedMetric)
    }

    @Test
    fun fetchLeaderboard_preservesEmptyBoardAndNullCurrentRank() = runBlocking {
        val expected = LeaderboardResponse(
            scope = LeaderboardScope.GLOBAL,
            status = "ACTIVE",
            metric = LeaderboardMetric.TOTAL_XP,
            leaderboard = emptyList(),
            currentUserRank = null
        )
        val repository = LeaderboardRepository(
            LeaderboardFakeBackend(expected),
            Dispatchers.Unconfined
        )

        val actual = repository.fetchLeaderboard(
            "session-token",
            LeaderboardScope.GLOBAL,
            LeaderboardMetric.TOTAL_XP
        )

        assertEquals(emptyList<LeaderboardEntry>(), actual.leaderboard)
        assertNull(actual.currentUserRank)
    }

    private fun response(metric: LeaderboardMetric) = LeaderboardResponse(
        scope = LeaderboardScope.GUILD,
        status = "ACTIVE",
        metric = metric,
        leaderboard = listOf(
            LeaderboardEntry(
                rank = 1,
                nik = "00123",
                nickname = "RUNNER",
                division = "OPERATIONS",
                totalXp = 100,
                totalDistanceKm = 10.5,
                totalActivities = 3,
                currentLevel = 2,
                currentLevelName = "SCOUT"
            )
        ),
        currentUserRank = CurrentUserRank(rank = 1, metricValue = 10.5)
    )
}

private class LeaderboardFakeBackend(
    private val response: LeaderboardResponse
) : OraBackendApi {
    var receivedSessionToken: String? = null
    var receivedScope: LeaderboardScope? = null
    var receivedMetric: LeaderboardMetric? = null

    override fun getLeaderboard(
        sessionToken: String,
        scope: LeaderboardScope,
        metric: LeaderboardMetric
    ): LeaderboardResponse {
        receivedSessionToken = sessionToken
        receivedScope = scope
        receivedMetric = metric
        return response
    }

    override fun login(nik: String, pin: String): BackendLoginResult = error("Not used")
    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant =
        error("Not used")
    override fun submitActivity(
        sessionToken: String,
        activity: ActivityEntity
    ): SubmitActivityStatus = error("Not used")
    override fun getUserStats(sessionToken: String): UserStats = error("Not used")
    override fun getQuests(): List<QuestMaster> = error("Not used")
}
