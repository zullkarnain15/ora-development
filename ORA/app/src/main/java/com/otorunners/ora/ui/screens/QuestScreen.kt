package com.otorunners.ora.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.otorunners.ora.R
import com.otorunners.ora.data.QuestMaster
import com.otorunners.ora.data.QuestUiState
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.OraScreenTitle
import com.otorunners.ora.ui.theme.OraCreamMuted
import com.otorunners.ora.ui.theme.OraDisplaySmall
import com.otorunners.ora.ui.theme.OraForest
import com.otorunners.ora.ui.theme.OraForestDeep
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraOrange
import com.otorunners.ora.ui.theme.OraOutline
import com.otorunners.ora.ui.theme.OraPanel
import com.otorunners.ora.ui.theme.OraPanelAlt
import com.otorunners.ora.ui.theme.OraTeal
import java.util.Locale

private val QuestTinyText = OraDisplaySmall.copy(fontSize = 8.sp, lineHeight = 10.sp)

@Composable
private fun QuestCompactCard(
    title: String,
    modifier: Modifier = Modifier,
    iconRes: Int? = null,
    containerColor: Color = OraPanel,
    borderColor: Color = OraOutline,
    borderWidth: androidx.compose.ui.unit.Dp = 1.5.dp,
    titleColor: Color = OraGold,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(5.dp),
        colors = CardDefaults.cardColors(containerColor = containerColor),
        border = BorderStroke(borderWidth, borderColor)
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                if (iconRes != null) {
                    OraIcon(
                        drawableRes = iconRes,
                        contentDescription = title,
                        modifier = Modifier.size(18.dp)
                    )
                }
                Text(
                    text = title,
                    style = QuestTinyText,
                    fontWeight = FontWeight.Bold,
                    color = titleColor
                )
            }
            content()
        }
    }
}

@Composable
private fun QuestCompactBadge(text: String, color: Color = OraGold) {
    Text(
        text = text,
        style = QuestTinyText,
        fontWeight = FontWeight.Bold,
        color = color
    )
}

@Composable
private fun QuestCompactStatLine(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            color = OraCreamMuted,
            style = QuestTinyText,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = value,
            color = MaterialTheme.colorScheme.onSurface,
            style = QuestTinyText,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun QuestScreen(
    uiState: QuestUiState,
    onRefresh: () -> Unit,
    onClaim: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    LaunchedEffect(Unit) { onRefresh() }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        OraScreenTitle(
            title = "QUEST BOARD",
            subtitle = "ACTIVE MISSIONS FROM ORA MASTER",
            iconRes = R.drawable.quest
        )

        if (uiState.isLoading && uiState.quests.isEmpty()) {
            QuestCompactCard(title = "LOADING QUESTS", iconRes = R.drawable.quest) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = OraGold,
                        strokeWidth = 2.dp
                    )
                    Text("CONTACTING QUEST MASTER...", color = OraCreamMuted, style = QuestTinyText)
                }
            }
        }

        uiState.errorMessage?.let { message ->
            QuestCompactCard(title = "QUEST BOARD OFFLINE", iconRes = R.drawable.warning) {
                Text(message, color = OraCreamMuted, style = QuestTinyText)
                Button(
                    onClick = onRefresh,
                    enabled = !uiState.isLoading,
                    modifier = Modifier.height(32.dp),
                    shape = RoundedCornerShape(3.dp),
                    contentPadding = PaddingValues(horizontal = 10.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = OraGold,
                        contentColor = OraForest
                    )
                ) {
                    Text("RETRY", style = QuestTinyText, fontWeight = FontWeight.Bold)
                }
            }
        }

        if (!uiState.isLoading && uiState.errorMessage == null && uiState.quests.isEmpty()) {
            QuestCompactCard(title = "NO ACTIVE QUESTS", iconRes = R.drawable.quest) {
                Text("THE QUEST BOARD IS CLEAR.", color = OraCreamMuted, style = QuestTinyText)
            }
        }

        uiState.quests.forEach { quest ->
            QuestMasterCard(
                quest = quest,
                isClaimingThisQuest = uiState.claimingQuestId == quest.questId,
                isClaimDisabled = uiState.claimingQuestId != null,
                claimMessage = uiState.claimMessage.takeIf {
                    uiState.claimMessageQuestId == quest.questId
                },
                onClaim = { onClaim(quest.questId) }
            )
        }
    }
}

@Composable
private fun QuestMasterCard(
    quest: QuestMaster,
    isClaimingThisQuest: Boolean,
    isClaimDisabled: Boolean,
    claimMessage: String?,
    onClaim: () -> Unit
) {
    val icon = if (quest.questType == "GUILD_DISTANCE") R.drawable.guild else R.drawable.quest
    val visualState = quest.questVisualState()
    val colors = visualState.colors()
    QuestCompactCard(
        title = quest.questName,
        iconRes = icon,
        containerColor = colors.container,
        borderColor = colors.accent,
        borderWidth = if (visualState == QuestVisualState.CLAIMABLE) 2.dp else 1.5.dp,
        titleColor = colors.title
    ) {
        QuestCompactBadge(text = visualState.badgeText, color = colors.accent)
        QuestCompactStatLine(label = "Mission", value = quest.questType.displayName())
        QuestCompactStatLine(label = "Target", value = quest.targetLabel())
        if (quest.progress != null) {
            QuestCompactStatLine(label = "Progress", value = quest.progressLabel())
            LinearProgressIndicator(
                progress = { quest.visualProgress(visualState) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(7.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = colors.accent,
                trackColor = colors.track
            )
        }
        Text(
            text = quest.rewardStateText(visualState),
            color = colors.reward,
            style = QuestTinyText,
            fontWeight = if (
                visualState == QuestVisualState.CLAIMABLE ||
                visualState == QuestVisualState.CLAIMED
            ) {
                FontWeight.Bold
            } else {
                FontWeight.Medium
            }
        )
        QuestCompactStatLine(label = "Period", value = quest.periodType.displayName())
        if (quest.startDate.isNotBlank() || quest.endDate.isNotBlank()) {
            QuestCompactStatLine(label = "Active", value = quest.dateRange())
        }
        if (quest.canClaimReward()) {
            Button(
                onClick = onClaim,
                enabled = !isClaimDisabled,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(34.dp),
                shape = RoundedCornerShape(3.dp),
                contentPadding = PaddingValues(horizontal = 8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = OraGold,
                    contentColor = OraForest
                )
            ) {
                if (isClaimingThisQuest) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = OraForest,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        "CLAIM +${quest.rewardXp} XP",
                        style = QuestTinyText,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
        claimMessage?.let { message ->
            Text(
                text = message,
                color = OraGold,
                style = QuestTinyText,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

internal enum class QuestVisualState(val badgeText: String) {
    NOT_STARTED("NOT STARTED"),
    IN_PROGRESS("IN PROGRESS"),
    CLAIMABLE("QUEST COMPLETE!"),
    CLAIMED("CLAIMED ✓"),
    UNSUPPORTED("GUILD QUEST COMING SOON"),
    NO_GUILD("NO GUILD ASSIGNED"),
    UNKNOWN("QUEST TYPE NOT READY")
}

private data class QuestVisualColors(
    val container: Color,
    val accent: Color,
    val title: Color,
    val reward: Color,
    val track: Color
)

internal fun QuestMaster.questVisualState(): QuestVisualState = when {
    claimed -> QuestVisualState.CLAIMED
    status == "UNSUPPORTED_GROUP_SCOPE" -> QuestVisualState.UNSUPPORTED
    status == "NO_GUILD" -> QuestVisualState.NO_GUILD
    status == "UNKNOWN_TYPE" -> QuestVisualState.UNKNOWN
    completed -> QuestVisualState.CLAIMABLE
    (progress ?: 0.0) > 0.0 -> QuestVisualState.IN_PROGRESS
    else -> QuestVisualState.NOT_STARTED
}

private fun QuestVisualState.colors(): QuestVisualColors = when (this) {
    QuestVisualState.CLAIMABLE -> QuestVisualColors(
        container = OraPanel,
        accent = OraOrange,
        title = OraGold,
        reward = OraGold,
        track = OraOrange.copy(alpha = 0.18f)
    )
    QuestVisualState.CLAIMED -> QuestVisualColors(
        container = OraPanel,
        accent = OraTeal,
        title = OraTeal,
        reward = OraTeal,
        track = OraTeal.copy(alpha = 0.18f)
    )
    QuestVisualState.IN_PROGRESS -> QuestVisualColors(
        container = OraPanel,
        accent = OraGold,
        title = OraGold,
        reward = OraCreamMuted,
        track = OraPanelAlt
    )
    QuestVisualState.NOT_STARTED -> QuestVisualColors(
        container = OraForest,
        accent = OraOutline,
        title = OraCreamMuted,
        reward = OraCreamMuted,
        track = OraPanelAlt
    )
    QuestVisualState.UNSUPPORTED,
    QuestVisualState.NO_GUILD,
    QuestVisualState.UNKNOWN -> QuestVisualColors(
        container = OraForestDeep,
        accent = OraCreamMuted.copy(alpha = 0.55f),
        title = OraCreamMuted,
        reward = OraCreamMuted,
        track = OraOutline.copy(alpha = 0.4f)
    )
}

internal fun QuestMaster.visualProgress(visualState: QuestVisualState): Float = when (visualState) {
    QuestVisualState.CLAIMABLE,
    QuestVisualState.CLAIMED -> 1f
    QuestVisualState.UNSUPPORTED,
    QuestVisualState.NO_GUILD,
    QuestVisualState.UNKNOWN -> 0f
    else -> ((progressPercent ?: 0.0) / 100.0).toFloat().coerceIn(0f, 1f)
}

internal fun QuestMaster.rewardStateText(visualState: QuestVisualState): String {
    if (claimBlockedReason == "GUILD_REWARD_NOT_READY") {
        return "GUILD REWARD COMING SOON"
    }
    return when (visualState) {
    QuestVisualState.CLAIMABLE -> "Reward ready: +$rewardXp XP"
    QuestVisualState.CLAIMED -> "Reward collected: +$rewardXp XP"
    QuestVisualState.UNSUPPORTED -> "Group reward is not available yet"
    QuestVisualState.NO_GUILD -> "Join a guild to begin this quest"
    QuestVisualState.UNKNOWN -> "Reward unavailable for this quest type"
    else -> "Reward: +$rewardXp XP"
    }
}

internal fun QuestMaster.questStatusLabel(): String = when {
    claimed -> "CLAIMED"
    status == "UNSUPPORTED_GROUP_SCOPE" -> "GUILD QUEST COMING SOON"
    status == "NO_GUILD" -> "NO GUILD ASSIGNED"
    status == "UNKNOWN_TYPE" -> "UNKNOWN TYPE"
    completed -> "QUEST COMPLETE"
    (progress ?: 0.0) <= 0.0 -> "NOT STARTED"
    else -> "IN PROGRESS"
}

internal fun QuestMaster.canClaimReward(): Boolean {
    return completed &&
        !claimed &&
        claimable != false &&
        status != "UNKNOWN_TYPE" &&
        status != "UNSUPPORTED_GROUP_SCOPE"
}

private fun QuestMaster.progressLabel(): String {
    val current = formatQuestNumber(progress ?: 0.0)
    val target = formatQuestNumber(targetValue)
    val suffix = unit.takeIf { it.isNotBlank() }?.let { " $it" }.orEmpty()
    val percent = formatQuestNumber((progressPercent ?: 0.0).coerceIn(0.0, 100.0))
    return "$current / $target$suffix ($percent%)"
}

private fun QuestMaster.targetLabel(): String {
    val number = formatQuestNumber(targetValue)
    return listOf(number, unit).filter { it.isNotBlank() }.joinToString(" ")
}

private fun formatQuestNumber(value: Double): String = if (value % 1.0 == 0.0) {
    value.toLong().toString()
} else {
    String.format(Locale.US, "%.2f", value).trimEnd('0').trimEnd('.')
}

private fun QuestMaster.dateRange(): String = when {
    startDate.isNotBlank() && endDate.isNotBlank() -> "$startDate - $endDate"
    startDate.isNotBlank() -> "FROM $startDate"
    else -> "UNTIL $endDate"
}

private fun String.displayName(): String =
    replace('_', ' ').uppercase(Locale.US).ifBlank { "ACTIVE" }
