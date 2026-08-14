package com.otorunners.ora.data

import com.otorunners.ora.data.local.ActivityDao
import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.local.ActivityTotals
import com.otorunners.ora.data.local.SYNC_STATUS_PENDING
import com.otorunners.ora.data.local.SYNC_STATUS_SYNCED
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityRepositoryTest {
    @Test
    fun finishedActivityMapping_savesExpectedFields() = runBlocking {
        val dao = FakeActivityDao()
        val repository = repository(dao, fixedId = "activity-1", fixedNow = 9_000L)

        val result = repository.saveFinishedActivity(sampleFinishedActivity(ownerNik = "12345678"))

        assertTrue(result is ActivitySaveResult.Saved)
        val activity = (result as ActivitySaveResult.Saved).activity
        assertEquals("activity-1", activity.activityId)
        assertEquals("12345678", activity.ownerNik)
        assertEquals("RUNNER7", activity.nicknameSnapshot)
        assertEquals("ROAD", activity.divisionGuildSnapshot)
        assertEquals(1_000L, activity.startDateTimeMillis)
        assertEquals(7_000L, activity.endDateTimeMillis)
        assertEquals(1_000f, activity.distanceMeters)
        assertEquals(360_000L, activity.activeDurationMillis)
        assertEquals(360, activity.averagePaceSecondsPerKm)
        assertEquals(9_000L, activity.createdAtMillis)
        assertEquals(SYNC_STATUS_PENDING, activity.syncStatus)
    }

    @Test
    fun aggregation_sumsDistanceForRequestedOwnerOnly() = runBlocking {
        val dao = FakeActivityDao()
        seed(dao, activity("a1", "A", distanceMeters = 1_000f))
        seed(dao, activity("a2", "A", distanceMeters = 2_500f))
        seed(dao, activity("b1", "B", distanceMeters = 9_000f))

        assertEquals(3_500.0, dao.getTotalDistance("A").first(), 0.001)
    }

    @Test
    fun aggregation_sumsDurationForRequestedOwnerOnly() = runBlocking {
        val dao = FakeActivityDao()
        seed(dao, activity("a1", "A", activeDurationMillis = 60_000L))
        seed(dao, activity("a2", "A", activeDurationMillis = 120_000L))
        seed(dao, activity("b1", "B", activeDurationMillis = 900_000L))

        assertEquals(180_000L, dao.getTotalActiveDuration("A").first())
        assertEquals(ActivityTotals(2, 0.0, 180_000L), dao.getActivityTotals("A").first())
    }

    @Test
    fun latestActivity_usesNewestStartTimeForRequestedOwner() = runBlocking {
        val dao = FakeActivityDao()
        seed(dao, activity("old", "A", startDateTimeMillis = 1_000L))
        seed(dao, activity("new", "A", startDateTimeMillis = 3_000L))
        seed(dao, activity("other-user", "B", startDateTimeMillis = 9_000L))

        assertEquals("new", dao.getLatestActivity("A").first()?.activityId)
    }

    @Test
    fun activityHistory_isSeparatedByOwnerNik() = runBlocking {
        val dao = FakeActivityDao()
        seed(dao, activity("a1", "A"))
        seed(dao, activity("b1", "B"))

        val ownerBActivities = dao.getAllActivitiesNewestFirst("B").first()

        assertEquals(1, ownerBActivities.size)
        assertEquals("b1", ownerBActivities.first().activityId)
    }

    @Test
    fun duplicateActivityId_doesNotInsertSecondRecord() = runBlocking {
        val dao = FakeActivityDao()
        val repository = repository(dao, fixedId = "same-id")

        val first = repository.saveFinishedActivity(sampleFinishedActivity(ownerNik = "A"))
        val second = repository.saveFinishedActivity(sampleFinishedActivity(ownerNik = "A"))

        assertTrue(first is ActivitySaveResult.Saved)
        assertTrue(second is ActivitySaveResult.Duplicate)
        assertEquals(1, dao.getAllActivitiesNewestFirst("A").first().size)
    }

    private fun repository(
        dao: ActivityDao,
        fixedId: String = "activity-id",
        fixedNow: Long = 10_000L
    ): ActivityRepository {
        return ActivityRepository(
            activityDao = dao,
            idProvider = { fixedId },
            nowProvider = { fixedNow },
            ioDispatcher = Dispatchers.Unconfined
        )
    }

    private suspend fun seed(dao: FakeActivityDao, activity: ActivityEntity) {
        dao.insertActivity(activity)
    }

    private fun sampleFinishedActivity(ownerNik: String): FinishedRunActivity {
        return FinishedRunActivity(
            ownerNik = ownerNik,
            nicknameSnapshot = "RUNNER7",
            divisionGuildSnapshot = "ROAD",
            startDateTimeMillis = 1_000L,
            endDateTimeMillis = 7_000L,
            distanceMeters = 1_000f,
            activeDurationMillis = 360_000L,
            averagePaceSecondsPerKm = 360
        )
    }

    private fun activity(
        activityId: String,
        ownerNik: String,
        startDateTimeMillis: Long = 1_000L,
        distanceMeters: Float = 0f,
        activeDurationMillis: Long = 0L
    ): ActivityEntity {
        return ActivityEntity(
            activityId = activityId,
            ownerNik = ownerNik,
            nicknameSnapshot = null,
            divisionGuildSnapshot = null,
            startDateTimeMillis = startDateTimeMillis,
            endDateTimeMillis = startDateTimeMillis + activeDurationMillis,
            distanceMeters = distanceMeters,
            activeDurationMillis = activeDurationMillis,
            averagePaceSecondsPerKm = null,
            createdAtMillis = startDateTimeMillis
        )
    }

    private class FakeActivityDao : ActivityDao {
        private val activities = MutableStateFlow<List<ActivityEntity>>(emptyList())

        override suspend fun insertActivity(activity: ActivityEntity): Long {
            if (activities.value.any { it.activityId == activity.activityId }) return -1L
            activities.value = activities.value + activity
            return activities.value.size.toLong()
        }

        override suspend fun getPendingActivities(ownerNik: String): List<ActivityEntity> {
            return activities.value.filter {
                it.ownerNik == ownerNik && it.syncStatus != SYNC_STATUS_SYNCED
            }
        }

        override suspend fun markActivitySynced(activityId: String, ownerNik: String): Int {
            val index = activities.value.indexOfFirst {
                it.activityId == activityId && it.ownerNik == ownerNik
            }
            if (index < 0) return 0
            activities.value = activities.value.toMutableList().also {
                it[index] = it[index].copy(syncStatus = SYNC_STATUS_SYNCED)
            }
            return 1
        }

        override fun getLatestActivity(ownerNik: String): Flow<ActivityEntity?> {
            return activities.map { list ->
                list.filter { it.ownerNik == ownerNik }
                    .maxWithOrNull(compareBy<ActivityEntity> { it.startDateTimeMillis }.thenBy { it.createdAtMillis })
            }
        }

        override fun getAllActivitiesNewestFirst(ownerNik: String): Flow<List<ActivityEntity>> {
            return activities.map { list ->
                list.filter { it.ownerNik == ownerNik }
                    .sortedWith(compareByDescending<ActivityEntity> { it.startDateTimeMillis }.thenByDescending { it.createdAtMillis })
            }
        }

        override fun getTotalActivityCount(ownerNik: String): Flow<Int> {
            return activities.map { list -> list.count { it.ownerNik == ownerNik } }
        }

        override fun getTotalDistance(ownerNik: String): Flow<Double> {
            return activities.map { list ->
                list.filter { it.ownerNik == ownerNik }.sumOf { it.distanceMeters.toDouble() }
            }
        }

        override fun getTotalActiveDuration(ownerNik: String): Flow<Long> {
            return activities.map { list ->
                list.filter { it.ownerNik == ownerNik }.sumOf { it.activeDurationMillis }
            }
        }

        override fun getActivityTotals(ownerNik: String): Flow<ActivityTotals> {
            return activities.map { list ->
                val owned = list.filter { it.ownerNik == ownerNik }
                ActivityTotals(
                    activityCount = owned.size,
                    totalDistanceMeters = owned.sumOf { it.distanceMeters.toDouble() },
                    totalActiveDurationMillis = owned.sumOf { it.activeDurationMillis }
                )
            }
        }
    }
}
