package com.otorunners.ora.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.otorunners.ora.R
import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.local.ActivityTotals
import com.otorunners.ora.data.ActivitySyncUiState
import com.otorunners.ora.data.UserStatsUiState
import com.otorunners.ora.data.local.SYNC_STATUS_SYNCED
import com.otorunners.ora.run.formatDistanceKm
import com.otorunners.ora.run.formatDuration
import com.otorunners.ora.run.formatPaceSecondsPerKm
import com.otorunners.ora.ui.components.CompactStat
import com.otorunners.ora.ui.components.OraCard
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.OraScreenTitle
import com.otorunners.ora.ui.components.StatLine
import com.otorunners.ora.ui.components.XpProgress
import com.otorunners.ora.ui.theme.OraForestDeep
import com.otorunners.ora.ui.theme.OraGold
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun ProfileScreen(
    nickname: String,
    divisionGuild: String,
    activities: List<ActivityEntity>,
    activityTotals: ActivityTotals,
    userStatsState: UserStatsUiState,
    syncState: ActivitySyncUiState,
    onSync: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                OraScreenTitle(
                    title = "ADVENTURER PROFILE",
                    iconRes = R.drawable.you,
                    modifier = Modifier.weight(1f)
                )
                IconButton(
                    onClick = onOpenSettings,
                    modifier = Modifier.size(48.dp)
                ) {
                    OraIcon(
                        drawableRes = R.drawable.settings,
                        contentDescription = "Settings",
                        modifier = Modifier.size(30.dp)
                    )
                }
            }
        }

        item {
            OraCard(title = "ADVENTURE LOG", iconRes = R.drawable.adventure) {
                Button(
                    onClick = onSync,
                    enabled = !syncState.isSyncing,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = OraGold,
                        contentColor = OraForestDeep
                    )
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (syncState.isSyncing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                color = OraForestDeep,
                                strokeWidth = 3.dp
                            )
                            Text(text = "SYNCING...", fontWeight = FontWeight.Bold)
                        } else {
                            OraIcon(
                                drawableRes = R.drawable.resume,
                                contentDescription = "Sync adventures",
                                modifier = Modifier.size(22.dp)
                            )
                            Text(text = "SYNC NOW", fontWeight = FontWeight.Bold)
                        }
                    }
                }

                syncState.message?.let { message ->
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OraIcon(
                            drawableRes = if (syncState.isError) R.drawable.warning else R.drawable.success,
                            contentDescription = "Sync status",
                            modifier = Modifier.size(22.dp)
                        )
                        Text(
                            text = message,
                            color = if (syncState.isError) MaterialTheme.colorScheme.error else OraGold,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                if (activities.isEmpty()) {
                    Text(text = "NO ADVENTURE YET", style = MaterialTheme.typography.titleMedium)
                    StatLine(label = "Start your first adventure.", value = "", iconRes = R.drawable.adventure)
                }
            }
        }

        item {
            OraCard(title = "STATUS", iconRes = R.drawable.level) {
                val stats = userStatsState.stats
                Text(text = stats?.nickname?.ifBlank { nickname } ?: nickname, style = MaterialTheme.typography.titleMedium)

                if (userStatsState.isLoading && stats == null) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = OraGold,
                            strokeWidth = 3.dp
                        )
                        Text(text = "LOADING STATS...", fontWeight = FontWeight.SemiBold)
                    }
                } else if (stats != null) {
                    StatLine(
                        label = "LEVEL ${stats.currentLevel}",
                        value = stats.currentLevelName.ifBlank { "ADVENTURER" },
                        iconRes = R.drawable.level
                    )
                    StatLine(
                        label = "GUILD",
                        value = stats.division.ifBlank { divisionGuild },
                        iconRes = R.drawable.guild
                    )
                    StatLine(label = "TOTAL XP", value = "${stats.totalXp} XP", iconRes = R.drawable.xp)
                    XpProgress(
                        current = "${stats.totalXp} XP",
                        target = stats.nextLevelXp?.let { "$it XP" } ?: "MAX LEVEL",
                        progress = stats.nextLevelXp
                            ?.takeIf { it > 0 }
                            ?.let { (stats.totalXp.toFloat() / it).coerceIn(0f, 1f) }
                            ?: 1f,
                        iconRes = R.drawable.xp
                    )
                }

                userStatsState.errorMessage?.let { message ->
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OraIcon(
                            drawableRes = R.drawable.warning,
                            contentDescription = "Stats unavailable",
                            modifier = Modifier.size(22.dp)
                        )
                        Text(
                            text = message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }

        item {
            val stats = userStatsState.stats
            OraCard(title = "RPG STATS", iconRes = R.drawable.trophy) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    CompactStat(
                        value = stats?.let { formatBackendDistanceKm(it.totalDistanceKm) } ?: "-- KM",
                        label = "TOTAL DISTANCE",
                        modifier = Modifier.weight(1f),
                        iconRes = R.drawable.distance
                    )
                    CompactStat(
                        value = stats?.totalActivities?.toString() ?: "--",
                        label = "ADVENTURES",
                        modifier = Modifier.weight(1f),
                        iconRes = R.drawable.adventure
                    )
                }
                CompactStat(
                    value = stats?.let { formatDuration((it.totalDurationSec * 1_000).toLong()) } ?: "--:--",
                    label = "TOTAL TIME",
                    modifier = Modifier.fillMaxWidth(),
                    iconRes = R.drawable.duration
                )
            }
        }

        items(activities, key = { it.activityId }) { activity ->
            OraCard(title = formatActivityDate(activity.startDateTimeMillis), iconRes = R.drawable.adventure) {
                StatLine(label = "Distance", value = formatDistanceKm(activity.distanceMeters), iconRes = R.drawable.distance)
                StatLine(label = "Duration", value = formatDuration(activity.activeDurationMillis), iconRes = R.drawable.duration)
                StatLine(label = "Pace", value = formatPaceSecondsPerKm(activity.averagePaceSecondsPerKm), iconRes = R.drawable.pace)
                StatLine(
                    label = "Sync",
                    value = if (activity.syncStatus == SYNC_STATUS_SYNCED) "SYNCED" else "PENDING",
                    iconRes = if (activity.syncStatus == SYNC_STATUS_SYNCED) R.drawable.success else R.drawable.warning
                )
            }
        }
    }
}

private fun formatActivityDate(epochMillis: Long): String {
    val formatter = DateTimeFormatter.ofPattern("MMM dd - HH:mm", Locale.US)
    return Instant.ofEpochMilli(epochMillis)
        .atZone(ZoneId.systemDefault())
        .format(formatter)
        .uppercase(Locale.US)
}

private fun formatBackendDistanceKm(distanceKm: Double): String {
    return String.format(Locale.US, "%.2f KM", distanceKm.coerceAtLeast(0.0))
}
