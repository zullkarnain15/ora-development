package com.otorunners.ora.auth

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = AuthRepository(
        authStore = LocalAuthStore(application)
    )

    private val _uiState = MutableStateFlow(initialState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    fun login(nik: String, pin: String) {
        if (_uiState.value.operation != null) return
        _uiState.value = _uiState.value.copy(
            errorMessage = null,
            operation = AuthOperation.LOGIN
        )
        viewModelScope.launch { applyOutcome(repository.login(nik, pin)) }
    }

    fun activateNickname(nickname: String) {
        val pending = _uiState.value.pendingActivation ?: return
        if (_uiState.value.operation != null) return
        _uiState.value = _uiState.value.copy(
            errorMessage = null,
            operation = AuthOperation.ACTIVATION
        )
        viewModelScope.launch { applyOutcome(repository.activate(pending, nickname)) }
    }

    fun renameNickname(nickname: String) {
        val user = _uiState.value.user ?: return
        if (_uiState.value.operation != null) return
        _uiState.value = _uiState.value.copy(
            errorMessage = null,
            operation = AuthOperation.RENAME
        )
        viewModelScope.launch { applyOutcome(repository.renameNickname(user, nickname)) }
    }

    fun clearError() {
        if (_uiState.value.errorMessage != null) {
            _uiState.value = _uiState.value.copy(errorMessage = null)
        }
    }

    fun logout() {
        repository.logout()
        _uiState.value = AuthUiState()
    }

    private fun initialState(): AuthUiState {
        val restoredUser = repository.restoreSession()
        return if (restoredUser != null) {
            AuthUiState(stage = AuthStage.AUTHENTICATED, user = restoredUser)
        } else {
            AuthUiState()
        }
    }

    private fun applyOutcome(outcome: AuthOutcome) {
        _uiState.value = when (outcome) {
            is AuthOutcome.Authenticated -> AuthUiState(
                stage = AuthStage.AUTHENTICATED,
                user = outcome.user
            )
            is AuthOutcome.ActivationRequired -> AuthUiState(
                stage = AuthStage.ACTIVATION,
                pendingActivation = outcome.pending
            )
            is AuthOutcome.Error -> _uiState.value.copy(
                errorMessage = outcome.message,
                operation = null
            )
        }
    }
}
