package com.otorunners.ora.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart

class OraDatabase private constructor(context: Context) : SQLiteOpenHelper(
    context.applicationContext,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    private val dao = SqliteActivityDao(this)

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE activities (
                activityId TEXT NOT NULL PRIMARY KEY,
                ownerNik TEXT NOT NULL,
                nicknameSnapshot TEXT,
                divisionGuildSnapshot TEXT,
                startDateTimeMillis INTEGER NOT NULL,
                endDateTimeMillis INTEGER NOT NULL,
                distanceMeters REAL NOT NULL,
                activeDurationMillis INTEGER NOT NULL,
                averagePaceSecondsPerKm INTEGER,
                createdAtMillis INTEGER NOT NULL,
                syncStatus TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX index_activities_owner_start ON activities(ownerNik, startDateTimeMillis)")
        db.execSQL("CREATE INDEX index_activities_owner_created ON activities(ownerNik, createdAtMillis)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun activityDao(): ActivityDao = dao

    companion object {
        private const val DATABASE_NAME = "ora.db"
        private const val DATABASE_VERSION = 1

        @Volatile
        private var instance: OraDatabase? = null

        fun getInstance(context: Context): OraDatabase {
            return instance ?: synchronized(this) {
                instance ?: OraDatabase(context).also { instance = it }
            }
        }
    }
}

private class SqliteActivityDao(
    private val database: OraDatabase
) : ActivityDao {
    private val updates = MutableSharedFlow<Unit>(replay = 1).apply { tryEmit(Unit) }

    override suspend fun insertActivity(activity: ActivityEntity): Long {
        val rowId = database.writableDatabase.insertWithOnConflict(
            TABLE_ACTIVITIES,
            null,
            activity.toContentValues(),
            SQLiteDatabase.CONFLICT_IGNORE
        )
        if (rowId != INSERT_IGNORED) updates.tryEmit(Unit)
        return rowId
    }

    override suspend fun getPendingActivities(ownerNik: String): List<ActivityEntity> {
        return queryActivities(
            ownerNik = ownerNik,
            selectionSuffix = "AND syncStatus IN (?, ?)",
            selectionArgsSuffix = arrayOf(SYNC_STATUS_PENDING, SYNC_STATUS_LOCAL_ONLY)
        )
    }

    override suspend fun markActivitySynced(activityId: String, ownerNik: String): Int {
        val values = ContentValues().apply { put("syncStatus", SYNC_STATUS_SYNCED) }
        val updatedRows = database.writableDatabase.update(
            TABLE_ACTIVITIES,
            values,
            "activityId = ? AND ownerNik = ? AND syncStatus != ?",
            arrayOf(activityId, ownerNik, SYNC_STATUS_SYNCED)
        )
        if (updatedRows > 0) updates.tryEmit(Unit)
        return updatedRows
    }

    override fun getLatestActivity(ownerNik: String): Flow<ActivityEntity?> {
        return updates.onStart { emit(Unit) }
            .map { queryLatestActivity(ownerNik) }
            .flowOn(Dispatchers.IO)
    }

    override fun getAllActivitiesNewestFirst(ownerNik: String): Flow<List<ActivityEntity>> {
        return updates.onStart { emit(Unit) }
            .map { queryActivities(ownerNik) }
            .flowOn(Dispatchers.IO)
    }

    override fun getTotalActivityCount(ownerNik: String): Flow<Int> {
        return updates.onStart { emit(Unit) }
            .map { queryLong(ownerNik, "COUNT(*)").toInt() }
            .flowOn(Dispatchers.IO)
    }

    override fun getTotalDistance(ownerNik: String): Flow<Double> {
        return updates.onStart { emit(Unit) }
            .map { queryDouble(ownerNik, "COALESCE(SUM(distanceMeters), 0.0)") }
            .flowOn(Dispatchers.IO)
    }

    override fun getTotalActiveDuration(ownerNik: String): Flow<Long> {
        return updates.onStart { emit(Unit) }
            .map { queryLong(ownerNik, "COALESCE(SUM(activeDurationMillis), 0)") }
            .flowOn(Dispatchers.IO)
    }

    override fun getActivityTotals(ownerNik: String): Flow<ActivityTotals> {
        return updates.onStart { emit(Unit) }
            .map {
                ActivityTotals(
                    activityCount = queryLong(ownerNik, "COUNT(*)").toInt(),
                    totalDistanceMeters = queryDouble(ownerNik, "COALESCE(SUM(distanceMeters), 0.0)"),
                    totalActiveDurationMillis = queryLong(ownerNik, "COALESCE(SUM(activeDurationMillis), 0)")
                )
            }
            .flowOn(Dispatchers.IO)
    }

    private fun queryLatestActivity(ownerNik: String): ActivityEntity? {
        return database.readableDatabase.query(
            TABLE_ACTIVITIES,
            null,
            "ownerNik = ?",
            arrayOf(ownerNik),
            null,
            null,
            "startDateTimeMillis DESC, createdAtMillis DESC",
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toActivityEntity() else null
        }
    }

    private fun queryActivities(
        ownerNik: String,
        selectionSuffix: String = "",
        selectionArgsSuffix: Array<String> = emptyArray()
    ): List<ActivityEntity> {
        return database.readableDatabase.query(
            TABLE_ACTIVITIES,
            null,
            "ownerNik = ? $selectionSuffix",
            arrayOf(ownerNik, *selectionArgsSuffix),
            null,
            null,
            "startDateTimeMillis DESC, createdAtMillis DESC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.toActivityEntity())
            }
        }
    }

    private fun queryLong(ownerNik: String, expression: String): Long {
        return database.readableDatabase.rawQuery(
            "SELECT $expression FROM $TABLE_ACTIVITIES WHERE ownerNik = ?",
            arrayOf(ownerNik)
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getLong(0) else 0L
        }
    }

    private fun queryDouble(ownerNik: String, expression: String): Double {
        return database.readableDatabase.rawQuery(
            "SELECT $expression FROM $TABLE_ACTIVITIES WHERE ownerNik = ?",
            arrayOf(ownerNik)
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getDouble(0) else 0.0
        }
    }

    private fun ActivityEntity.toContentValues(): ContentValues {
        return ContentValues().apply {
            put("activityId", activityId)
            put("ownerNik", ownerNik)
            put("nicknameSnapshot", nicknameSnapshot)
            put("divisionGuildSnapshot", divisionGuildSnapshot)
            put("startDateTimeMillis", startDateTimeMillis)
            put("endDateTimeMillis", endDateTimeMillis)
            put("distanceMeters", distanceMeters)
            put("activeDurationMillis", activeDurationMillis)
            put("averagePaceSecondsPerKm", averagePaceSecondsPerKm)
            put("createdAtMillis", createdAtMillis)
            put("syncStatus", syncStatus)
        }
    }

    private fun Cursor.toActivityEntity(): ActivityEntity {
        return ActivityEntity(
            activityId = getString(getColumnIndexOrThrow("activityId")),
            ownerNik = getString(getColumnIndexOrThrow("ownerNik")),
            nicknameSnapshot = getNullableString("nicknameSnapshot"),
            divisionGuildSnapshot = getNullableString("divisionGuildSnapshot"),
            startDateTimeMillis = getLong(getColumnIndexOrThrow("startDateTimeMillis")),
            endDateTimeMillis = getLong(getColumnIndexOrThrow("endDateTimeMillis")),
            distanceMeters = getFloat(getColumnIndexOrThrow("distanceMeters")),
            activeDurationMillis = getLong(getColumnIndexOrThrow("activeDurationMillis")),
            averagePaceSecondsPerKm = getNullableInt("averagePaceSecondsPerKm"),
            createdAtMillis = getLong(getColumnIndexOrThrow("createdAtMillis")),
            syncStatus = getString(getColumnIndexOrThrow("syncStatus"))
        )
    }

    private fun Cursor.getNullableString(columnName: String): String? {
        val index = getColumnIndexOrThrow(columnName)
        return if (isNull(index)) null else getString(index)
    }

    private fun Cursor.getNullableInt(columnName: String): Int? {
        val index = getColumnIndexOrThrow(columnName)
        return if (isNull(index)) null else getInt(index)
    }

    companion object {
        private const val TABLE_ACTIVITIES = "activities"
        private const val INSERT_IGNORED = -1L
    }
}
