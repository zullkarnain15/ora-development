package com.otorunners.ora.auth

import com.otorunners.ora.backend.BackendLoginResult
import com.otorunners.ora.backend.BackendParticipant
import com.otorunners.ora.backend.OraBackendApi
import com.otorunners.ora.backend.SubmitActivityStatus
import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.UserStats
import com.otorunners.ora.data.QuestMaster
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthRepositoryTest {
    @Test
    fun firstLogin_requiresActivationAndCarriesBackendToken() = runBlocking {
        val repository = repository(FakeAuthStore(), FakeBackendApi())

        val outcome = repository.login("12345678", "1234") as AuthOutcome.ActivationRequired

        assertEquals("backend-token", outcome.pending.sessionToken)
    }

    @Test
    fun returningUser_reusesBackendNicknameAfterLogout() = runBlocking {
        val store = FakeAuthStore()
        val backend = FakeBackendApi()
        val repository = repository(store, backend)
        val firstLogin = repository.login("12345678", "1234") as AuthOutcome.ActivationRequired
        val activation = repository.activate(firstLogin.pending, "  runner7  ") as AuthOutcome.Authenticated

        assertEquals("RUNNER7", activation.user.nickname)
        repository.logout()
        assertNull(store.loadSession())

        val returningLogin = repository.login("12345678", "1234") as AuthOutcome.Authenticated
        assertEquals("RUNNER7", returningLogin.user.nickname)
        assertEquals("Human Resources", returningLogin.user.divisionGuild)
    }

    @Test
    fun renameNickname_preservesBackendSessionToken() = runBlocking {
        val store = FakeAuthStore()
        val repository = repository(store, FakeBackendApi())
        val firstLogin = repository.login("12345678", "1234") as AuthOutcome.ActivationRequired
        val activation = repository.activate(firstLogin.pending, "RUNNER7") as AuthOutcome.Authenticated

        val rename = repository.renameNickname(activation.user, " otohero ") as AuthOutcome.Authenticated

        assertEquals("OTOHERO", rename.user.nickname)
        assertEquals("backend-token", store.loadSession()?.sessionToken)
        assertTrue(!store.isNicknameTaken("RUNNER7", "87654321"))
    }

    private fun repository(store: AuthStore, backend: OraBackendApi): AuthRepository {
        return AuthRepository(
            authStore = store,
            backendApi = backend,
            ioDispatcher = Dispatchers.Unconfined,
            nowProvider = { 1_000L }
        )
    }
}

private class FakeBackendApi : OraBackendApi {
    private var nickname: String? = null

    override fun login(nik: String, pin: String): BackendLoginResult {
        return BackendLoginResult(
            sessionToken = "backend-token",
            expiresInSeconds = 2_592_000L,
            participant = participant(nik),
            requiresNicknameActivation = nickname == null
        )
    }

    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant {
        this.nickname = nickname
        return participant("12345678")
    }

    override fun submitActivity(
        sessionToken: String,
        activity: ActivityEntity
    ): SubmitActivityStatus = SubmitActivityStatus.SAVED

    override fun getUserStats(sessionToken: String): UserStats = error("Not used")
    override fun getQuests(): List<QuestMaster> = error("Not used")

    private fun participant(nik: String) = BackendParticipant(
        nik = nik,
        nickname = nickname,
        divisionGuild = "Human Resources",
        active = true
    )
}

private class FakeAuthStore : AuthStore {
    private var session: UserSession? = null
    private val profiles = mutableMapOf<String, UserSession>()
    private val nicknameOwners = mutableMapOf<String, String>()

    override fun loadSession(): UserSession? = session

    override fun saveSession(user: UserSession) {
        session = user
    }

    override fun clearSession() {
        session = null
    }

    override fun nicknameFor(nik: String): String? = profiles[nik]?.nickname

    override fun divisionFor(nik: String): String? = profiles[nik]?.divisionGuild

    override fun saveActivatedProfile(user: UserSession) {
        profiles[user.nik]?.nickname?.let { previousNickname ->
            if (canonicalNickname(previousNickname) != canonicalNickname(user.nickname)) {
                nicknameOwners.remove(canonicalNickname(previousNickname))
            }
        }
        profiles[user.nik] = user
        nicknameOwners[canonicalNickname(user.nickname)] = user.nik
    }

    override fun isNicknameTaken(canonicalNickname: String, excludingNik: String): Boolean {
        val owner = nicknameOwners[canonicalNickname]
        return owner != null && owner != excludingNik
    }
}
