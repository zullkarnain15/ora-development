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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.otorunners.ora.R
import com.otorunners.ora.data.GuildSummary
import com.otorunners.ora.data.GuildMember
import com.otorunners.ora.data.GuildUiState
import com.otorunners.ora.data.LeaderboardEntry
import com.otorunners.ora.data.LeaderboardMetric
import com.otorunners.ora.data.LeaderboardScope
import com.otorunners.ora.data.LeaderboardUiState
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.OraScreenTitle
import com.otorunners.ora.ui.theme.OraCreamMuted
import com.otorunners.ora.ui.theme.OraDisplaySmall
import com.otorunners.ora.ui.theme.OraForest
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraOutline
import com.otorunners.ora.ui.theme.OraPanel
import com.otorunners.ora.ui.theme.OraPanelAlt
import java.util.Locale

private enum class GuildTab(val label: String) {
    MEMBERS("MEMBERS"),
    LEADERBOARD("LEADERBOARD"),
    GUILDS("GUILDS")
}

private val GuildTinyText = OraDisplaySmall.copy(fontSize = 8.sp, lineHeight = 10.sp)

@Composable
fun GuildScreen(
    uiState: GuildUiState,
    leaderboardState: LeaderboardUiState,
    onRefresh: () -> Unit,
    onRefreshBoard: () -> Unit,
    onSelectBoardScope: (LeaderboardScope) -> Unit,
    onSelectBoardMetric: (LeaderboardMetric) -> Unit,
    modifier: Modifier = Modifier
) {
    LaunchedEffect(Unit) {
        onRefresh()
        onRefreshBoard()
    }
    var selectedTab by remember { mutableStateOf(GuildTab.MEMBERS) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        OraScreenTitle(
            title = "GUILD",
            subtitle = "YOUR DIVISION PARTY HALL",
            iconRes = R.drawable.guild
        )

        if (uiState.isLoading && uiState.guild == null) {
            GuildCompactCard(title = "LOADING GUILD...", iconRes = R.drawable.guild) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = OraGold,
                        strokeWidth = 2.dp
                    )
                    Text("GATHERING PARTY RECORDS...", color = OraCreamMuted, style = GuildTinyText)
                }
            }
        }

        uiState.errorMessage?.let { message ->
            GuildCompactCard(title = "GUILD HALL OFFLINE", iconRes = R.drawable.warning) {
                Text(message, color = OraCreamMuted, style = GuildTinyText)
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
                    Text("RETRY", style = GuildTinyText, fontWeight = FontWeight.Bold)
                }
            }
        }

        if (
            !uiState.isLoading &&
            uiState.errorMessage == null &&
            (uiState.status == "UNASSIGNED" || uiState.guild == null)
        ) {
            GuildCompactCard(title = "NO GUILD ASSIGNED", iconRes = R.drawable.guild) {
                Text(
                    "YOU ARE NOT ASSIGNED TO A GUILD YET.",
                    color = OraCreamMuted,
                    style = GuildTinyText
                )
            }
        }

        uiState.guild?.let { guild ->
            GuildSummaryCompactCard(guild = guild, status = uiState.status)

            GuildTabs(
                selectedTab = selectedTab,
                onSelectTab = { tab ->
                    selectedTab = tab
                }
            )

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                when (selectedTab) {
                    GuildTab.MEMBERS -> MembersTab(uiState.members)
                    GuildTab.LEADERBOARD -> LeaderboardBoard(
                        uiState = leaderboardState,
                        onRefresh = onRefreshBoard,
                        onSelectScope = onSelectBoardScope,
                        onSelectMetric = onSelectBoardMetric
                    )
                    GuildTab.GUILDS -> GuildsTab(
                        currentGuild = guild,
                        guilds = uiState.guilds,
                        isLoading = uiState.isGuildDirectoryLoading,
                        errorMessage = uiState.guildDirectoryErrorMessage
                    )
                }
            }
        }
    }
}

@Composable
private fun GuildCompactCard(
    title: String,
    modifier: Modifier = Modifier,
    iconRes: Int? = null,
    borderColor: Color = OraOutline,
    borderWidth: androidx.compose.ui.unit.Dp = 1.5.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(5.dp),
        colors = CardDefaults.cardColors(containerColor = OraPanel),
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
                    style = GuildTinyText,
                    fontWeight = FontWeight.Bold,
                    color = OraGold
                )
            }
            content()
        }
    }
}

@Composable
private fun GuildCompactBadge(text: String, color: Color = OraGold) {
    Text(
        text = text,
        style = GuildTinyText,
        fontWeight = FontWeight.Bold,
        color = color
    )
}

@Composable
private fun GuildSummaryCompactCard(
    guild: GuildSummary,
    status: String?
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(5.dp),
        colors = CardDefaults.cardColors(containerColor = OraPanel),
        border = BorderStroke(1.5.dp, OraOutline)
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OraIcon(
                    drawableRes = R.drawable.guild,
                    contentDescription = "Guild",
                    modifier = Modifier.size(20.dp)
                )
                Text(
                    text = guild.displayName.ifBlank { guild.guildName }.uppercase(Locale.ROOT),
                    style = GuildTinyText,
                    fontWeight = FontWeight.Bold,
                    color = OraGold,
                    modifier = Modifier.weight(1f)
                )
                GuildCompactBadge(
                    text = if (status == "GUILD_INACTIVE") "INACTIVE" else "GUILD"
                )
            }

            CompactGuildStatLine(
                label = "Members",
                value = "${guild.memberCount} / ${guild.activeMemberCount} ACTIVE",
                iconRes = R.drawable.you
            )
            CompactGuildStatLine(
                label = "Level ${guild.currentLevel.coerceAtLeast(1)}",
                value = guild.currentLevelName.ifBlank { "ADVENTURER" },
                iconRes = R.drawable.level
            )
            CompactGuildStatLine(
                label = "XP",
                value = "${guild.totalXp} XP",
                iconRes = R.drawable.xp
            )
            CompactGuildStatLine(
                label = "Distance",
                value = "${formatGuildNumber(guild.totalDistanceKm)} KM",
                iconRes = R.drawable.distance
            )
        }
    }
}

@Composable
private fun CompactGuildStatLine(label: String, value: String, iconRes: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.weight(1f)
        ) {
            OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(16.dp))
            Text(text = label, color = OraCreamMuted, style = GuildTinyText)
        }
        Text(
            text = value,
            color = MaterialTheme.colorScheme.onSurface,
            style = GuildTinyText,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun GuildTabs(
    selectedTab: GuildTab,
    onSelectTab: (GuildTab) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        GuildTab.entries.forEach { tab ->
            val selected = selectedTab == tab
            Button(
                onClick = { onSelectTab(tab) },
                modifier = Modifier
                    .weight(1f)
                    .height(34.dp),
                shape = RoundedCornerShape(3.dp),
                contentPadding = PaddingValues(horizontal = 1.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (selected) OraGold else OraPanelAlt,
                    contentColor = if (selected) OraForest else OraCreamMuted
                )
            ) {
                Text(
                    text = tab.label,
                    style = GuildTinyText,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun MembersTab(members: List<GuildMember>) {
    Text(
        text = "ACTIVE MEMBERS",
        style = GuildTinyText,
        color = OraGold,
        fontWeight = FontWeight.Bold
    )

    if (members.isEmpty()) {
        GuildCompactCard(title = "NO ACTIVE MEMBERS", iconRes = R.drawable.you) {
            Text("THE GUILD HALL IS QUIET.", color = OraCreamMuted, style = GuildTinyText)
        }
    } else {
        members.forEach { member ->
            GuildMemberCard(member)
        }
    }
}

@Composable
private fun GuildsTab(
    currentGuild: com.otorunners.ora.data.GuildSummary,
    guilds: List<com.otorunners.ora.data.GuildSummary>,
    isLoading: Boolean,
    errorMessage: String?
) {
    Text(
        text = "GUILDS",
        style = GuildTinyText,
        color = OraGold,
        fontWeight = FontWeight.Bold
    )

    if (isLoading && guilds.isEmpty()) {
        GuildCompactCard(title = "LOADING GUILDS...", iconRes = R.drawable.guild) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = OraGold,
                    strokeWidth = 2.dp
                )
                Text("CHECKING GUILD BOARD...", color = OraCreamMuted, style = GuildTinyText)
            }
        }
    } else if (errorMessage != null && guilds.isEmpty()) {
        GuildCompactCard(title = "GUILD BOARD OFFLINE", iconRes = R.drawable.warning) {
            Text(errorMessage, color = OraCreamMuted, style = GuildTinyText)
        }
    } else if (guilds.isEmpty()) {
        GuildCompactCard(title = "NO OTHER GUILDS YET", iconRes = R.drawable.guild) {
            Text("THE GUILD BOARD IS QUIET.", color = OraCreamMuted, style = GuildTinyText)
        }
    } else {
        guilds.forEach { guild ->
            GuildDirectoryCard(
                guild = guild,
                isCurrentGuild = guild.sameGuildAs(currentGuild)
            )
        }
    }
}

@Composable
private fun GuildDirectoryCard(
    guild: com.otorunners.ora.data.GuildSummary,
    isCurrentGuild: Boolean
) {
    GuildCompactCard(
        title = guild.displayName.ifBlank { guild.guildName }.uppercase(Locale.ROOT),
        iconRes = R.drawable.guild,
        borderColor = if (isCurrentGuild) OraGold else OraOutline,
        borderWidth = if (isCurrentGuild) 2.dp else 1.5.dp
    ) {
        if (isCurrentGuild) GuildCompactBadge(text = "YOUR GUILD")
        CompactGuildStatLine(label = "Members", value = guild.memberCount.toString(), iconRes = R.drawable.you)
        CompactGuildStatLine(label = "Active Members", value = guild.activeMemberCount.toString(), iconRes = R.drawable.you)
        CompactGuildStatLine(
            label = "Guild Level ${guild.currentLevel.coerceAtLeast(1)}",
            value = guild.currentLevelName.ifBlank { "ADVENTURER" },
            iconRes = R.drawable.level
        )
        CompactGuildStatLine(
            label = "Total XP",
            value = "${guild.totalXp} XP",
            iconRes = R.drawable.xp
        )
    }
}

@Composable
private fun LeaderboardBoard(
    uiState: LeaderboardUiState,
    onRefresh: () -> Unit,
    onSelectScope: (LeaderboardScope) -> Unit,
    onSelectMetric: (LeaderboardMetric) -> Unit
) {
    Text(
        text = "ADVENTURER BOARD",
        style = GuildTinyText,
        color = OraGold,
        fontWeight = FontWeight.Bold
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        LeaderboardScope.entries.forEach { scope ->
            val selected = uiState.scope == scope
            Button(
                onClick = { onSelectScope(scope) },
                modifier = Modifier
                    .weight(1f)
                    .height(34.dp),
                shape = RoundedCornerShape(3.dp),
                contentPadding = PaddingValues(horizontal = 2.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (selected) OraGold else OraPanelAlt,
                    contentColor = if (selected) OraForest else OraCreamMuted
                )
            ) {
                Text(
                    text = scope.label,
                    style = GuildTinyText,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        LeaderboardMetric.entries.forEach { metric ->
            val selected = uiState.metric == metric
            Button(
                onClick = { onSelectMetric(metric) },
                modifier = Modifier
                    .weight(1f)
                    .height(34.dp),
                shape = RoundedCornerShape(3.dp),
                contentPadding = PaddingValues(horizontal = 2.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (selected) OraGold else OraPanelAlt,
                    contentColor = if (selected) OraForest else OraCreamMuted
                )
            ) {
                Text(
                    text = metric.label,
                    style = GuildTinyText,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }

    if (uiState.isLoading && uiState.entries.isEmpty()) {
        GuildCompactCard(title = "LOADING BOARD...", iconRes = R.drawable.trophy) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = OraGold,
                    strokeWidth = 2.dp
                )
                Text("COUNTING ADVENTURERS...", color = OraCreamMuted, style = GuildTinyText)
            }
        }
    }

    uiState.errorMessage?.let { message ->
        GuildCompactCard(title = "BOARD OFFLINE", iconRes = R.drawable.warning) {
            Text(message, color = OraCreamMuted, style = GuildTinyText)
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
                Text("RETRY", style = GuildTinyText, fontWeight = FontWeight.Bold)
            }
        }
    }

    if (!uiState.isLoading && uiState.errorMessage == null && uiState.entries.isEmpty()) {
        val noGuild = uiState.scope == LeaderboardScope.GUILD && uiState.status == "NO_GUILD"
        GuildCompactCard(
            title = if (noGuild) "NO GUILD ASSIGNED" else "NO ADVENTURERS YET",
            iconRes = if (noGuild) R.drawable.guild else R.drawable.trophy
        ) {
            Text(
                if (noGuild) {
                    "YOU ARE NOT ASSIGNED TO A GUILD YET."
                } else {
                    "THE ADVENTURER BOARD IS EMPTY."
                },
                color = OraCreamMuted,
                style = GuildTinyText
            )
        }
    }

    if (uiState.errorMessage == null) {
        uiState.currentUserRank?.let { currentRank ->
            GuildCompactCard(
                title = "YOUR ${uiState.scope.label} RANK",
                iconRes = R.drawable.achievement
            ) {
                CompactGuildStatLine(label = "Rank", value = "#${currentRank.rank}", iconRes = R.drawable.trophy)
                CompactGuildStatLine(
                    label = uiState.metric.label,
                    value = formatLeaderboardMetric(currentRank.metricValue, uiState.metric),
                    iconRes = uiState.metric.iconRes()
                )
            }
        }
        uiState.entries.forEach { entry ->
            LeaderboardEntryCard(
                entry = entry,
                metric = uiState.metric,
                isCurrentUser = entry.nik == uiState.ownerNik
            )
        }
    }
}

@Composable
private fun LeaderboardEntryCard(
    entry: LeaderboardEntry,
    metric: LeaderboardMetric,
    isCurrentUser: Boolean
) {
    GuildCompactCard(
        title = "#${entry.rank} ${entry.nickname.ifBlank { "ADVENTURER" }.uppercase(Locale.ROOT)}",
        iconRes = R.drawable.trophy,
        borderColor = if (isCurrentUser) OraGold else OraOutline,
        borderWidth = if (isCurrentUser) 2.dp else 1.5.dp
    ) {
        if (isCurrentUser) GuildCompactBadge(text = "YOU")
        CompactGuildStatLine(
            label = "Division",
            value = entry.division.ifBlank { "UNASSIGNED" },
            iconRes = R.drawable.guild
        )
        CompactGuildStatLine(
            label = "Level ${entry.currentLevel.coerceAtLeast(1)}",
            value = entry.currentLevelName.ifBlank { "ADVENTURER" },
            iconRes = R.drawable.level
        )
        CompactGuildStatLine(
            label = metric.label,
            value = entry.metricDisplayValue(metric),
            iconRes = metric.iconRes()
        )
    }
}

@Composable
private fun GuildMemberCard(member: GuildMember) {
    GuildCompactCard(
        title = member.nickname.ifBlank { "ADVENTURER" }.uppercase(Locale.ROOT),
        iconRes = R.drawable.you
    ) {
        CompactGuildStatLine(
            label = "Level ${member.currentLevel.coerceAtLeast(1)}",
            value = member.currentLevelName.ifBlank { "ADVENTURER" },
            iconRes = R.drawable.level
        )
        CompactGuildStatLine(
            label = "Distance",
            value = "${formatGuildNumber(member.totalDistanceKm)} KM",
            iconRes = R.drawable.distance
        )
        CompactGuildStatLine(
            label = "Activities",
            value = member.totalActivities.toString(),
            iconRes = R.drawable.adventure
        )
        CompactGuildStatLine(
            label = "Total XP",
            value = "${member.totalXp} XP",
            iconRes = R.drawable.xp
        )
    }
}

private fun formatGuildNumber(value: Double): String = if (value % 1.0 == 0.0) {
    value.toLong().toString()
} else {
    String.format(Locale.US, "%.2f", value).trimEnd('0').trimEnd('.')
}

private fun LeaderboardEntry.metricDisplayValue(metric: LeaderboardMetric): String = when (metric) {
    LeaderboardMetric.TOTAL_XP -> "$totalXp XP"
    LeaderboardMetric.TOTAL_DISTANCE -> "${formatGuildNumber(totalDistanceKm)} KM"
    LeaderboardMetric.TOTAL_ACTIVITIES -> "$totalActivities RUNS"
}

private fun com.otorunners.ora.data.GuildSummary.sameGuildAs(
    other: com.otorunners.ora.data.GuildSummary
): Boolean {
    val ownKeys = listOf(guildId, guildName, displayName)
        .map { it.trim().uppercase(Locale.ROOT) }
        .filter { it.isNotBlank() }
    val otherKeys = listOf(other.guildId, other.guildName, other.displayName)
        .map { it.trim().uppercase(Locale.ROOT) }
        .filter { it.isNotBlank() }
    return ownKeys.any { it in otherKeys }
}

private fun formatLeaderboardMetric(value: Double, metric: LeaderboardMetric): String = when (metric) {
    LeaderboardMetric.TOTAL_XP -> "${value.toLong()} XP"
    LeaderboardMetric.TOTAL_DISTANCE -> "${formatGuildNumber(value)} KM"
    LeaderboardMetric.TOTAL_ACTIVITIES -> "${value.toLong()} RUNS"
}

private fun LeaderboardMetric.iconRes(): Int = when (this) {
    LeaderboardMetric.TOTAL_XP -> R.drawable.xp
    LeaderboardMetric.TOTAL_DISTANCE -> R.drawable.distance
    LeaderboardMetric.TOTAL_ACTIVITIES -> R.drawable.adventure
}
