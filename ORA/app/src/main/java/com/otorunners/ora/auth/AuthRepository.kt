package com.otorunners.ora.auth

import com.otorunners.ora.backend.AppsScriptBackendApi
import com.otorunners.ora.backend.BackendException
import com.otorunners.ora.backend.OraBackendApi
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AuthRepository(
    private val authStore: AuthStore,
    private val backendApi: OraBackendApi = AppsScriptBackendApi(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val nowProvider: () -> Long = { System.currentTimeMillis() }
) {
    fun restoreSession(): UserSession? = authStore.loadSession()

    suspend fun login(nikInput: String, pin: String): AuthOutcome = withContext(ioDispatcher) {
        val nik = nikInput.trim()
        if (nik.isEmpty()) return@withContext AuthOutcome.Error("Enter your NIK.")
        pinValidationError(pin)?.let { return@withContext AuthOutcome.Error(it) }

        try {
            val result = backendApi.login(nik, pin)
            val expiresAtMillis = nowProvider() + result.expiresInSeconds * 1_000L
            if (result.requiresNicknameActivation || result.participant.nickname.isNullOrBlank()) {
                AuthOutcome.ActivationRequired(
                    PendingActivation(
                        nik = result.participant.nik,
                        divisionGuild = result.participant.divisionGuild,
                        sessionToken = result.sessionToken,
                        sessionExpiresAtMillis = expiresAtMillis
                    )
                )
            } else {
                authenticate(
                    UserSession(
                        nik = result.participant.nik,
                        nickname = result.participant.nickname,
                        divisionGuild = result.participant.divisionGuild,
                        active = result.participant.active,
                        sessionToken = result.sessionToken,
                        sessionExpiresAtMillis = expiresAtMillis
                    )
                )
            }
        } catch (error: Exception) {
            AuthOutcome.Error(error.toUserMessage())
        }
    }

    suspend fun activate(pending: PendingActivation, nicknameInput: String): AuthOutcome =
        withContext(ioDispatcher) {
            nicknameValidationError(nicknameInput)?.let {
                return@withContext AuthOutcome.Error(it)
            }
            val nickname = canonicalNickname(nicknameInput)
            try {
                val participant = backendApi.activateNickname(pending.sessionToken, nickname)
                authenticate(
                    UserSession(
                        nik = participant.nik,
                        nickname = participant.nickname ?: nickname,
                        divisionGuild = participant.divisionGuild,
                        active = participant.active,
                        sessionToken = pending.sessionToken,
                        sessionExpiresAtMillis = pending.sessionExpiresAtMillis
                    )
                )
            } catch (error: Exception) {
                AuthOutcome.Error(error.toUserMessage())
            }
        }

    fun renameNickname(currentUser: UserSession, nicknameInput: String): AuthOutcome {
        nicknameValidationError(nicknameInput)?.let { return AuthOutcome.Error(it) }

        val nickname = canonicalNickname(nicknameInput)
        if (authStore.isNicknameTaken(nickname, currentUser.nik)) {
            return AuthOutcome.Error("Nickname is already in use.")
        }

        return authenticate(currentUser.copy(nickname = nickname))
    }

    fun logout() {
        authStore.clearSession()
    }

    private fun authenticate(user: UserSession): AuthOutcome.Authenticated {
        authStore.saveActivatedProfile(user)
        authStore.saveSession(user)
        return AuthOutcome.Authenticated(user)
    }

    private fun Exception.toUserMessage(): String {
        return when ((this as? BackendException)?.code) {
            "INVALID_CREDENTIALS" -> "NIK or PIN is incorrect."
            "ACCOUNT_INACTIVE" -> "This account is inactive."
            "NICKNAME_TAKEN" -> "Nickname is already in use."
            "INVALID_NICKNAME" -> message ?: "Nickname is invalid."
            "SESSION_EXPIRED", "UNAUTHORIZED" -> "Session expired. Please login again."
            else -> "Unable to connect to ORA. Check your connection and try again."
        }
    }
}
