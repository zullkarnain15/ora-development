package com.otorunners.ora.data

import com.otorunners.ora.data.local.ActivityDao
import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.local.SYNC_STATUS_PENDING
import java.util.UUID
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class FinishedRunActivity(
    val ownerNik: String,
    val nicknameSnapshot: String?,
    val divisionGuildSnapshot: String?,
    val startDateTimeMillis: Long,
    val endDateTimeMillis: Long,
    val distanceMeters: Float,
    val activeDurationMillis: Long,
    val averagePaceSecondsPerKm: Int?
)

sealed interface ActivitySaveResult {
    data class Saved(val activity: ActivityEntity) : ActivitySaveResult
    data class Duplicate(val activityId: String) : ActivitySaveResult
}

class ActivityRepository(
    private val activityDao: ActivityDao,
    private val idProvider: () -> String = { UUID.randomUUID().toString() },
    private val nowProvider: () -> Long = { System.currentTimeMillis() },
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    fun latestActivity(ownerNik: String) = activityDao.getLatestActivity(ownerNik)

    fun activitiesNewestFirst(ownerNik: String) = activityDao.getAllActivitiesNewestFirst(ownerNik)

    fun activityTotals(ownerNik: String) = activityDao.getActivityTotals(ownerNik)

    suspend fun saveFinishedActivity(activity: FinishedRunActivity): ActivitySaveResult {
        return withContext(ioDispatcher) {
            val entity = activity.toEntity(
                activityId = idProvider(),
                createdAtMillis = nowProvider()
            )
            val rowId = activityDao.insertActivity(entity)
            if (rowId == INSERT_IGNORED) {
                ActivitySaveResult.Duplicate(entity.activityId)
            } else {
                ActivitySaveResult.Saved(entity)
            }
        }
    }

    companion object {
        private const val INSERT_IGNORED = -1L
    }
}

fun FinishedRunActivity.toEntity(activityId: String, createdAtMillis: Long): ActivityEntity {
    return ActivityEntity(
        activityId = activityId,
        ownerNik = ownerNik,
        nicknameSnapshot = nicknameSnapshot,
        divisionGuildSnapshot = divisionGuildSnapshot,
        startDateTimeMillis = startDateTimeMillis,
        endDateTimeMillis = endDateTimeMillis,
        distanceMeters = distanceMeters.takeIf { it.isFinite() && it >= 0f } ?: 0f,
        activeDurationMillis = activeDurationMillis.coerceAtLeast(0L),
        averagePaceSecondsPerKm = averagePaceSecondsPerKm?.takeIf { it > 0 },
        createdAtMillis = createdAtMillis,
        syncStatus = SYNC_STATUS_PENDING
    )
}
