package com.otorunners.ora.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

interface AuthStore {
    fun loadSession(): UserSession?
    fun saveSession(user: UserSession)
    fun clearSession()
    fun nicknameFor(nik: String): String?
    fun divisionFor(nik: String): String?
    fun saveActivatedProfile(user: UserSession)
    fun isNicknameTaken(canonicalNickname: String, excludingNik: String): Boolean
}

class LocalAuthStore(context: Context) : AuthStore {
    private val preferences: SharedPreferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    override fun loadSession(): UserSession? {
        if (!preferences.getBoolean(KEY_LOGGED_IN, false)) return null

        val nik = preferences.getString(KEY_SESSION_NIK, null) ?: return null
        val nickname = preferences.getString(KEY_SESSION_NICKNAME, null) ?: return null
        val divisionGuild = preferences.getString(KEY_SESSION_DIVISION, null) ?: return null
        val sessionToken = preferences.getString(KEY_SESSION_TOKEN, null) ?: return null
        val expiresAtMillis = preferences.getLong(KEY_SESSION_EXPIRES_AT, 0L)
        if (expiresAtMillis <= System.currentTimeMillis()) {
            clearSession()
            return null
        }
        return UserSession(
            nik = nik,
            nickname = nickname,
            divisionGuild = divisionGuild,
            active = true,
            sessionToken = sessionToken,
            sessionExpiresAtMillis = expiresAtMillis
        )
    }

    override fun saveSession(user: UserSession) {
        preferences.edit {
            putBoolean(KEY_LOGGED_IN, true)
            putString(KEY_SESSION_NIK, user.nik)
            putString(KEY_SESSION_NICKNAME, user.nickname)
            putString(KEY_SESSION_DIVISION, user.divisionGuild)
            putString(KEY_SESSION_TOKEN, user.sessionToken)
            putLong(KEY_SESSION_EXPIRES_AT, user.sessionExpiresAtMillis)
        }
    }

    override fun clearSession() {
        preferences.edit {
            remove(KEY_LOGGED_IN)
            remove(KEY_SESSION_NIK)
            remove(KEY_SESSION_NICKNAME)
            remove(KEY_SESSION_DIVISION)
            remove(KEY_SESSION_TOKEN)
            remove(KEY_SESSION_EXPIRES_AT)
        }
    }

    override fun nicknameFor(nik: String): String? {
        return preferences.getString(profileNicknameKey(nik), null)
    }

    override fun divisionFor(nik: String): String? {
        return preferences.getString(profileDivisionKey(nik), null)
    }

    override fun saveActivatedProfile(user: UserSession) {
        val previousNickname = nicknameFor(user.nik)
        preferences.edit {
            if (previousNickname != null && canonicalNickname(previousNickname) != canonicalNickname(user.nickname)) {
                remove(nicknameOwnerKey(canonicalNickname(previousNickname)))
            }
            putString(profileNicknameKey(user.nik), user.nickname)
            putString(profileDivisionKey(user.nik), user.divisionGuild)
            putString(nicknameOwnerKey(canonicalNickname(user.nickname)), user.nik)
        }
    }

    override fun isNicknameTaken(canonicalNickname: String, excludingNik: String): Boolean {
        val ownerNik = preferences.getString(nicknameOwnerKey(canonicalNickname), null)
        return ownerNik != null && ownerNik != excludingNik
    }

    private fun profileNicknameKey(nik: String) = "profile_${nik}_nickname"
    private fun profileDivisionKey(nik: String) = "profile_${nik}_division"
    private fun nicknameOwnerKey(nickname: String) = "nickname_owner_$nickname"

    companion object {
        private const val PREFERENCES_NAME = "ora_auth"
        private const val KEY_LOGGED_IN = "session_logged_in"
        private const val KEY_SESSION_NIK = "session_nik"
        private const val KEY_SESSION_NICKNAME = "session_nickname"
        private const val KEY_SESSION_DIVISION = "session_division"
        private const val KEY_SESSION_TOKEN = "session_token"
        private const val KEY_SESSION_EXPIRES_AT = "session_expires_at"
    }
}
