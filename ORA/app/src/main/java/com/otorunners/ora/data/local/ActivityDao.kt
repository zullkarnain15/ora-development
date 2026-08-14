package com.otorunners.ora.data.local

import kotlinx.coroutines.flow.Flow

interface ActivityDao {
    suspend fun insertActivity(activity: ActivityEntity): Long

    suspend fun getPendingActivities(ownerNik: String): List<ActivityEntity>

    suspend fun markActivitySynced(activityId: String, ownerNik: String): Int

    fun getLatestActivity(ownerNik: String): Flow<ActivityEntity?>

    fun getAllActivitiesNewestFirst(ownerNik: String): Flow<List<ActivityEntity>>

    fun getTotalActivityCount(ownerNik: String): Flow<Int>

    fun getTotalDistance(ownerNik: String): Flow<Double>

    fun getTotalActiveDuration(ownerNik: String): Flow<Long>

    fun getActivityTotals(ownerNik: String): Flow<ActivityTotals>
}
