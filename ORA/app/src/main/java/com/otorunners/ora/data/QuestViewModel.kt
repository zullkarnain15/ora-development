package com.otorunners.ora.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class QuestViewModel(
    private val repository: QuestRepository = QuestRepository()
) : ViewModel() {
    private val _uiState = MutableStateFlow(QuestUiState())
    val uiState: StateFlow<QuestUiState> = _uiState.asStateFlow()

    fun refresh(sessionToken: String) {
        if (_uiState.value.isLoading) return
        _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
        viewModelScope.launch {
            try {
                _uiState.value = QuestUiState(
                    quests = repository.fetchQuestsWithProgress(sessionToken)
                )
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "QUESTS UNAVAILABLE - TRY AGAIN"
                )
            }
        }
    }

    fun claimReward(
        sessionToken: String,
        questId: String,
        onClaimed: () -> Unit
    ) {
        if (_uiState.value.claimingQuestId != null) return
        _uiState.value = _uiState.value.copy(
            claimingQuestId = questId,
            claimMessageQuestId = questId,
            claimMessage = null
        )
        viewModelScope.launch {
            try {
                val result = repository.claimReward(sessionToken, questId)
                _uiState.value = _uiState.value.copy(
                    quests = _uiState.value.quests.map { quest ->
                        if (quest.questId == result.questId) {
                            quest.copy(
                                claimed = true,
                                claimId = result.claimId,
                                claimedAt = result.claimedAt
                            )
                        } else {
                            quest
                        }
                    },
                    claimingQuestId = null,
                    claimMessageQuestId = questId,
                    claimMessage = "+${result.rewardXp} XP CLAIMED"
                )
                onClaimed()
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(
                    claimingQuestId = null,
                    claimMessageQuestId = questId,
                    claimMessage = "CLAIM FAILED - TRY AGAIN"
                )
            }
        }
    }
}
