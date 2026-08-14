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

class GuildRepositoryTest {
    @Test
    fun fetchGuildSummary_forwardsSessionAndReturnsRealData() = runBlocking {
        val expected = GuildSummaryResponse(
            status = "ACTIVE",
            guild = GuildSummary(
                guildId = "TRAIL NORTH",
                guildName = "TRAIL NORTH",
                memberCount = 3,
                activeMemberCount = 2,
                totalDistanceKm = 12.5,
                totalActivities = 4,
                totalXp = 175,
                displayName = "Trail North Crew",
                description = "Northern trail adventurers."
            ),
            members = listOf(
                GuildMember(
                    nik = "00123",
                    nickname = "RUNNER",
                    division = "TRAIL NORTH",
                    totalDistanceKm = 12.5,
                    totalActivities = 4,
                    totalXp = 175,
                    currentLevel = 2,
                    currentLevelName = "SCOUT"
                )
            )
        )
        val backend = GuildFakeBackend(expected)
        val repository = GuildRepository(backend, Dispatchers.Unconfined)

        assertEquals(expected, repository.fetchGuildSummary("session-token"))
        assertEquals("session-token", backend.receivedSessionToken)
    }

    @Test
    fun fetchGuildSummary_preservesUnassignedState() = runBlocking {
        val response = GuildSummaryResponse(
            status = "UNASSIGNED",
            guild = null,
            members = emptyList()
        )
        val repository = GuildRepository(GuildFakeBackend(response), Dispatchers.Unconfined)

        val actual = repository.fetchGuildSummary("session-token")

        assertEquals("UNASSIGNED", actual.status)
        assertNull(actual.guild)
        assertEquals(emptyList<GuildMember>(), actual.members)
    }
}

private class GuildFakeBackend(
    private val response: GuildSummaryResponse
) : OraBackendApi {
    var receivedSessionToken: String? = null

    override fun getGuildSummary(sessionToken: String): GuildSummaryResponse {
        receivedSessionToken = sessionToken
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
