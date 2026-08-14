package com.otorunners.ora.data

import com.otorunners.ora.auth.UserSession
import com.otorunners.ora.backend.AppsScriptBackendApi
import com.otorunners.ora.backend.OraBackendApi
import com.otorunners.ora.backend.SubmitActivityStatus
import com.otorunners.ora.data.local.ActivityDao
import com.otorunners.ora.data.local.ActivityEntity
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class ActivitySyncResult(
    val syncedCount: Int,
    val pendingCount: Int,
    val failedCount: Int = 0
)

class ActivitySyncManager(
    private val activityDao: ActivityDao,
    private val backendApi: OraBackendApi = AppsScriptBackendApi(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val logger: (String) -> Unit = {}
) {
    suspend fun syncPending(user: UserSession): ActivitySyncResult = withContext(ioDispatcher) {
        var syncedCount = 0
        var failedCount = 0
        val pending = activityDao.getPendingActivities(user.nik)
        pending.forEach { activity ->
            if (activity.ownerNik != user.nik || !activity.isValidForBackend()) return@forEach
            try {
                when (backendApi.submitActivity(user.sessionToken, activity)) {
                    SubmitActivityStatus.SAVED,
                    SubmitActivityStatus.DUPLICATE -> {
                        activityDao.markActivitySynced(activity.activityId, user.nik)
                        syncedCount += 1
                    }
                }
            } catch (error: Exception) {
                failedCount += 1
                logger("Activity sync pending: ${activity.activityId} (${error.javaClass.simpleName})")
            }
        }
        ActivitySyncResult(
            syncedCount = syncedCount,
            pendingCount = activityDao.getPendingActivities(user.nik).size,
            failedCount = failedCount
        )
    }

    private fun ActivityEntity.isValidForBackend(): Boolean {
        return activeDurationMillis > 0L && distanceMeters.isFinite() && distanceMeters > 0f
    }
}
