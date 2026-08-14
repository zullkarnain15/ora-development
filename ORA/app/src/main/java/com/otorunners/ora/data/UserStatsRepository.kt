package com.otorunners.ora.data

import com.otorunners.ora.backend.AppsScriptBackendApi
import com.otorunners.ora.backend.OraBackendApi
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class UserStatsRepository(
    private val backendApi: OraBackendApi = AppsScriptBackendApi(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun fetch(sessionToken: String): UserStats = withContext(ioDispatcher) {
        backendApi.getUserStats(sessionToken)
    }
}
