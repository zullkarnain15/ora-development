package com.otorunners.ora.auth

import java.util.Locale

fun pinValidationError(pin: String): String? {
    return when {
        pin.isEmpty() -> "Enter your PIN."
        pin.length != PIN_LENGTH -> "PIN must be exactly 4 digits."
        !pin.all(Char::isDigit) -> "PIN must contain numbers only."
        else -> null
    }
}

fun isValidPin(pin: String): Boolean = pinValidationError(pin) == null

fun normalizeNickname(nickname: String): String = nickname.trim()

fun canonicalNickname(nickname: String): String {
    return normalizeNickname(nickname).uppercase(Locale.ROOT)
}

fun nicknameValidationError(nickname: String): String? {
    val normalized = normalizeNickname(nickname)
    return when {
        normalized.isEmpty() -> "Enter a nickname."
        normalized.length > MAX_NICKNAME_LENGTH -> "Nickname can have up to 8 characters."
        !normalized.all(Char::isLetterOrDigit) -> "Use letters and numbers only."
        else -> null
    }
}

fun isValidNickname(nickname: String): Boolean = nicknameValidationError(nickname) == null

const val MAX_NICKNAME_LENGTH = 8
private const val PIN_LENGTH = 4
