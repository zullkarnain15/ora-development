package com.otorunners.ora.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class GuildViewModel(
    private val repository: GuildRepository = GuildRepository()
) : ViewModel() {
    private val _uiState = MutableStateFlow(GuildUiState())
    val uiState: StateFlow<GuildUiState> = _uiState.asStateFlow()

    fun refresh(sessionToken: String, ownerNik: String) {
        if (_uiState.value.isLoading && _uiState.value.ownerNik == ownerNik) return

        val current = _uiState.value.takeIf { it.ownerNik == ownerNik }
        _uiState.value = (current ?: GuildUiState(ownerNik = ownerNik)).copy(
            isLoading = true,
            errorMessage = null,
            isGuildDirectoryLoading = true,
            guildDirectoryErrorMessage = null
        )
        viewModelScope.launch {
            try {
                val response = repository.fetchGuildSummary(sessionToken)
                if (_uiState.value.ownerNik != ownerNik) return@launch
                _uiState.value = _uiState.value.copy(
                    status = response.status,
                    guild = response.guild,
                    members = response.members,
                    isLoading = false,
                    errorMessage = null
                )
            } catch (_: Exception) {
                if (_uiState.value.ownerNik != ownerNik) return@launch
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "GUILD DATA UNAVAILABLE - TRY AGAIN"
                )
            }

            try {
                val response = repository.fetchGuildDirectory(sessionToken)
                if (_uiState.value.ownerNik != ownerNik) return@launch
                _uiState.value = _uiState.value.copy(
                    guilds = response.guilds,
                    isGuildDirectoryLoading = false,
                    guildDirectoryErrorMessage = null
                )
            } catch (_: Exception) {
                if (_uiState.value.ownerNik != ownerNik) return@launch
                _uiState.value = _uiState.value.copy(
                    isGuildDirectoryLoading = false,
                    guildDirectoryErrorMessage = "GUILD LIST UNAVAILABLE - TRY AGAIN"
                )
            }
        }
    }
}
