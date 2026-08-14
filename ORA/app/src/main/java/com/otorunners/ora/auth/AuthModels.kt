package com.otorunners.ora.auth

data class MockUser(
    val nik: String,
    val pin: String,
    val divisionGuild: String,
    val nickname: String?,
    val active: Boolean
)

data class PendingActivation(
    val nik: String,
    val divisionGuild: String,
    val sessionToken: String,
    val sessionExpiresAtMillis: Long
)

data class UserSession(
    val nik: String,
    val nickname: String,
    val divisionGuild: String,
    val active: Boolean,
    val sessionToken: String,
    val sessionExpiresAtMillis: Long
)

enum class AuthStage {
    LOGIN,
    ACTIVATION,
    AUTHENTICATED
}

enum class AuthOperation {
    LOGIN,
    ACTIVATION,
    RENAME
}

data class AuthUiState(
    val stage: AuthStage = AuthStage.LOGIN,
    val user: UserSession? = null,
    val pendingActivation: PendingActivation? = null,
    val errorMessage: String? = null,
    val operation: AuthOperation? = null
)

sealed interface AuthOutcome {
    data class Authenticated(val user: UserSession) : AuthOutcome
    data class ActivationRequired(val pending: PendingActivation) : AuthOutcome
    data class Error(val message: String) : AuthOutcome
}
