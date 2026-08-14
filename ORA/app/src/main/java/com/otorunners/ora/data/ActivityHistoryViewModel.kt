package com.otorunners.ora.data

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.otorunners.ora.auth.UserSession
import com.otorunners.ora.data.local.OraDatabase
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class ActivitySyncUiState(
    val isSyncing: Boolean = false,
    val message: String? = null,
    val pendingCount: Int? = null,
    val isError: Boolean = false
)

class ActivityHistoryViewModel(application: Application) : AndroidViewModel(application) {
    private val activityDao = OraDatabase.getInstance(application).activityDao()
    private val repository = ActivityRepository(activityDao = activityDao)
    private val syncManager = ActivitySyncManager(activityDao = activityDao)
    private val userStatsRepository = UserStatsRepository()
    private val syncMutex = Mutex()
    private var statsOwnerNik: String? = null
    private val _syncUiState = MutableStateFlow(ActivitySyncUiState())
    val syncUiState: StateFlow<ActivitySyncUiState> = _syncUiState.asStateFlow()
    private val _userStatsUiState = MutableStateFlow(UserStatsUiState())
    val userStatsUiState: StateFlow<UserStatsUiState> = _userStatsUiState.asStateFlow()

    fun latestActivity(ownerNik: String) = repository.latestActivity(ownerNik)

    fun activitiesNewestFirst(ownerNik: String) = repository.activitiesNewestFirst(ownerNik)

    fun activityTotals(ownerNik: String) = repository.activityTotals(ownerNik)

    fun retryPendingSync(user: UserSession) {
        viewModelScope.launch {
            val result = syncMutex.withLock { syncManager.syncPending(user) }
            if (result.failedCount == 0 && statsOwnerNik == user.nik) fetchUserStats(user)
        }
    }

    fun refreshUserStats(user: UserSession) {
        statsOwnerNik = user.nik
        val previous = _userStatsUiState.value.stats?.takeIf { it.nik == user.nik }
        _userStatsUiState.value = UserStatsUiState(
            stats = previous,
            isLoading = true
        )
        viewModelScope.launch { fetchUserStats(user) }
    }

    fun manualSync(user: UserSession, onFinished: (() -> Unit)? = null) {
        if (_syncUiState.value.isSyncing) return
        _syncUiState.value = ActivitySyncUiState(
            isSyncing = true,
            message = "SYNCING ADVENTURES..."
        )
        viewModelScope.launch {
            try {
                val result = syncMutex.withLock { syncManager.syncPending(user) }
                if (
                    result.failedCount == 0 &&
                    result.pendingCount == 0 &&
                    statsOwnerNik == user.nik
                ) {
                    _userStatsUiState.value = _userStatsUiState.value.copy(
                        isLoading = true,
                        errorMessage = null
                    )
                    fetchUserStats(user)
                }
                _syncUiState.value = when {
                    result.failedCount > 0 -> ActivitySyncUiState(
                        message = "${result.pendingCount} ADVENTURE${if (result.pendingCount == 1) "" else "S"} PENDING",
                        pendingCount = result.pendingCount,
                        isError = true
                    )
                    result.pendingCount > 0 -> ActivitySyncUiState(
                        message = "${result.pendingCount} ADVENTURE${if (result.pendingCount == 1) "" else "S"} PENDING",
                        pendingCount = result.pendingCount
                    )
                    else -> ActivitySyncUiState(
                        message = "ALL ADVENTURES SYNCED",
                        pendingCount = 0
                    )
                }
            } catch (_: Exception) {
                _syncUiState.value = ActivitySyncUiState(
                    message = "SYNC FAILED - TRY AGAIN",
                    isError = true
                )
            } finally {
                onFinished?.invoke()
            }
        }
    }

    private suspend fun fetchUserStats(user: UserSession) {
        try {
            val stats = userStatsRepository.fetch(user.sessionToken)
            if (stats.nik != user.nik) throw IllegalStateException("User stats owner mismatch")
            if (statsOwnerNik == user.nik) {
                _userStatsUiState.value = UserStatsUiState(stats = stats)
            }
        } catch (_: Exception) {
            if (statsOwnerNik == user.nik) {
                _userStatsUiState.value = _userStatsUiState.value.copy(
                    isLoading = false,
                    errorMessage = "STATS UNAVAILABLE - TRY SYNC AGAIN"
                )
            }
        }
    }
}
