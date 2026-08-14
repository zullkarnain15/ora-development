package com.otorunners.ora.data

import com.otorunners.ora.auth.UserSession
import com.otorunners.ora.backend.BackendLoginResult
import com.otorunners.ora.backend.BackendParticipant
import com.otorunners.ora.backend.OraBackendApi
import com.otorunners.ora.backend.SubmitActivityStatus
import com.otorunners.ora.data.local.ActivityDao
import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.local.ActivityTotals
import com.otorunners.ora.data.local.SYNC_STATUS_PENDING
import com.otorunners.ora.data.local.SYNC_STATUS_SYNCED
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class ActivitySyncManagerTest {
    @Test
    fun savedResponse_marksOnlyActiveOwnersActivitySynced() = runBlocking {
        val dao = SyncFakeDao(
            mutableListOf(activity("mine", "A"), activity("other", "B"))
        )
        val backend = SyncFakeBackend(SubmitActivityStatus.SAVED)
        val manager = ActivitySyncManager(dao, backend, Dispatchers.Unconfined)

        val result = manager.syncPending(user("A"))

        assertEquals(listOf("mine"), backend.submittedIds)
        assertEquals(SYNC_STATUS_SYNCED, dao.activities.first { it.activityId == "mine" }.syncStatus)
        assertEquals(SYNC_STATUS_PENDING, dao.activities.first { it.activityId == "other" }.syncStatus)
        assertEquals(ActivitySyncResult(syncedCount = 1, pendingCount = 0), result)
    }

    @Test
    fun duplicateResponse_isAlsoMarkedSynced() = runBlocking {
        val dao = SyncFakeDao(mutableListOf(activity("already-there", "A")))
        val manager = ActivitySyncManager(
            dao,
            SyncFakeBackend(SubmitActivityStatus.DUPLICATE),
            Dispatchers.Unconfined
        )

        manager.syncPending(user("A"))

        assertEquals(SYNC_STATUS_SYNCED, dao.activities.single().syncStatus)
    }

    @Test
    fun backendFailure_keepsActivityPending() = runBlocking {
        val dao = SyncFakeDao(mutableListOf(activity("retry-later", "A")))
        val manager = ActivitySyncManager(
            dao,
            FailingSyncBackend(),
            Dispatchers.Unconfined,
            logger = {}
        )

        val result = manager.syncPending(user("A"))

        assertEquals(SYNC_STATUS_PENDING, dao.activities.single().syncStatus)
        assertEquals(1, result.pendingCount)
        assertEquals(1, result.failedCount)
    }

    private fun user(nik: String) = UserSession(
        nik = nik,
        nickname = "RUNNER",
        divisionGuild = "ROAD",
        active = true,
        sessionToken = "test-token",
        sessionExpiresAtMillis = Long.MAX_VALUE
    )

    private fun activity(id: String, ownerNik: String) = ActivityEntity(
        activityId = id,
        ownerNik = ownerNik,
        nicknameSnapshot = "RUNNER",
        divisionGuildSnapshot = "ROAD",
        startDateTimeMillis = 1_000L,
        endDateTimeMillis = 361_000L,
        distanceMeters = 1_000f,
        activeDurationMillis = 360_000L,
        averagePaceSecondsPerKm = 360,
        createdAtMillis = 362_000L
    )
}

private class SyncFakeBackend(
    private val status: SubmitActivityStatus
) : OraBackendApi {
    val submittedIds = mutableListOf<String>()

    override fun submitActivity(sessionToken: String, activity: ActivityEntity): SubmitActivityStatus {
        submittedIds += activity.activityId
        return status
    }

    override fun login(nik: String, pin: String): BackendLoginResult = error("Not used")
    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant = error("Not used")
    override fun getUserStats(sessionToken: String): UserStats = error("Not used")
    override fun getQuests(): List<QuestMaster> = error("Not used")
}

private class FailingSyncBackend : OraBackendApi {
    override fun submitActivity(sessionToken: String, activity: ActivityEntity): SubmitActivityStatus {
        error("Network unavailable")
    }

    override fun login(nik: String, pin: String): BackendLoginResult = error("Not used")
    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant = error("Not used")
    override fun getUserStats(sessionToken: String): UserStats = error("Not used")
    override fun getQuests(): List<QuestMaster> = error("Not used")
}

private class SyncFakeDao(
    val activities: MutableList<ActivityEntity>
) : ActivityDao {
    override suspend fun insertActivity(activity: ActivityEntity): Long {
        activities += activity
        return activities.size.toLong()
    }

    override suspend fun getPendingActivities(ownerNik: String): List<ActivityEntity> {
        return activities.filter { it.ownerNik == ownerNik && it.syncStatus != SYNC_STATUS_SYNCED }
    }

    override suspend fun markActivitySynced(activityId: String, ownerNik: String): Int {
        val index = activities.indexOfFirst { it.activityId == activityId && it.ownerNik == ownerNik }
        if (index < 0) return 0
        activities[index] = activities[index].copy(syncStatus = SYNC_STATUS_SYNCED)
        return 1
    }

    override fun getLatestActivity(ownerNik: String): Flow<ActivityEntity?> = flowOf(null)
    override fun getAllActivitiesNewestFirst(ownerNik: String): Flow<List<ActivityEntity>> = flowOf(emptyList())
    override fun getTotalActivityCount(ownerNik: String): Flow<Int> = flowOf(0)
    override fun getTotalDistance(ownerNik: String): Flow<Double> = flowOf(0.0)
    override fun getTotalActiveDuration(ownerNik: String): Flow<Long> = flowOf(0L)
    override fun getActivityTotals(ownerNik: String): Flow<ActivityTotals> =
        flowOf(ActivityTotals(0, 0.0, 0L))
}
