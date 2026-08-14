package com.otorunners.ora.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class LeaderboardViewModel(
    private val repository: LeaderboardRepository = LeaderboardRepository()
) : ViewModel() {
    private val _uiState = MutableStateFlow(LeaderboardUiState())
    val uiState: StateFlow<LeaderboardUiState> = _uiState.asStateFlow()

    fun refresh(
        sessionToken: String,
        ownerNik: String,
        scope: LeaderboardScope,
        metric: LeaderboardMetric
    ) {
        if (
            _uiState.value.isLoading &&
            _uiState.value.ownerNik == ownerNik &&
            _uiState.value.scope == scope &&
            _uiState.value.metric == metric
        ) return

        val current = _uiState.value.takeIf { it.ownerNik == ownerNik }
        _uiState.value = (current ?: LeaderboardUiState(ownerNik = ownerNik)).copy(
            scope = scope,
            metric = metric,
            status = if (current?.metric == metric && current.scope == scope) current.status else null,
            entries = if (current?.metric == metric && current.scope == scope) current.entries else emptyList(),
            currentUserRank = if (current?.metric == metric && current.scope == scope) {
                current.currentUserRank
            } else {
                null
            },
            isLoading = true,
            errorMessage = null
        )
        viewModelScope.launch {
            try {
                val response = repository.fetchLeaderboard(sessionToken, scope, metric)
                if (
                    _uiState.value.ownerNik != ownerNik ||
                    _uiState.value.scope != scope ||
                    _uiState.value.metric != metric
                ) return@launch
                _uiState.value = LeaderboardUiState(
                    ownerNik = ownerNik,
                    scope = response.scope,
                    metric = response.metric,
                    status = response.status,
                    entries = response.leaderboard,
                    currentUserRank = response.currentUserRank
                )
            } catch (_: Exception) {
                if (
                    _uiState.value.ownerNik != ownerNik ||
                    _uiState.value.scope != scope ||
                    _uiState.value.metric != metric
                ) return@launch
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "BOARD DATA UNAVAILABLE - TRY AGAIN"
                )
            }
        }
    }
}
