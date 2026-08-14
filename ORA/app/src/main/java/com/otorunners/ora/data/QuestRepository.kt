package com.otorunners.ora.data

import com.otorunners.ora.backend.AppsScriptBackendApi
import com.otorunners.ora.backend.OraBackendApi
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class QuestRepository(
    private val backendApi: OraBackendApi = AppsScriptBackendApi(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun fetchActiveQuests(): List<QuestMaster> = withContext(ioDispatcher) {
        backendApi.getQuests()
    }

    suspend fun fetchQuestsWithProgress(sessionToken: String): List<QuestMaster> =
        withContext(ioDispatcher) {
            try {
                backendApi.getQuestProgress(sessionToken)
            } catch (_: Exception) {
                backendApi.getQuests()
            }
        }

    suspend fun claimReward(sessionToken: String, questId: String): QuestClaimResult =
        withContext(ioDispatcher) {
            backendApi.claimQuestReward(sessionToken, questId)
        }
}
