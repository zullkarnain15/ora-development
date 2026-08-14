package com.otorunners.ora.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.otorunners.ora.R
import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.ActivitySyncUiState
import com.otorunners.ora.data.UserStatsUiState
import com.otorunners.ora.run.formatDistanceKm
import com.otorunners.ora.run.formatDuration
import com.otorunners.ora.run.formatPaceSecondsPerKm
import com.otorunners.ora.ui.components.OraCard
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.PixelBadge
import com.otorunners.ora.ui.components.StatLine
import com.otorunners.ora.ui.components.XpProgress
import com.otorunners.ora.ui.theme.OraForestDeep
import com.otorunners.ora.ui.theme.OraGold
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun HomeScreen(
    nickname: String,
    latestActivity: ActivityEntity?,
    userStatsState: UserStatsUiState,
    syncState: ActivitySyncUiState,
    modifier: Modifier = Modifier,
    onSync: () -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Image(
                    painter = painterResource(id = R.drawable.oto_runners),
                    contentDescription = "OTO Runners",
                    modifier = Modifier
                        .fillMaxWidth()
                        .sizeIn(maxHeight = 46.dp),
                    alignment = Alignment.CenterStart,
                    contentScale = ContentScale.Fit
                )
                Text(
                    text = "OTO RUNNERS ADVENTURE",
                    style = MaterialTheme.typography.labelSmall,
                    color = com.otorunners.ora.ui.theme.OraCreamMuted
                )
            }
            Button(
                onClick = onSync,
                enabled = !syncState.isSyncing,
                colors = ButtonDefaults.buttonColors(
                    containerColor = OraGold.copy(alpha = 0.9f),
                    contentColor = OraForestDeep
                ),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    horizontal = 12.dp,
                    vertical = 8.dp
                )
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (syncState.isSyncing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(17.dp),
                            color = OraForestDeep,
                            strokeWidth = 2.dp
                        )
                        Text("SYNCING...", fontWeight = FontWeight.Bold)
                    } else {
                        OraIcon(
                            drawableRes = R.drawable.resume,
                            contentDescription = "Sync now",
                            modifier = Modifier.size(19.dp)
                        )
                        Text("SYNC NOW", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        PixelBadge(text = "RPG - RUN PLAYING GAME")
        syncState.message?.let { message ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OraIcon(
                    drawableRes = if (syncState.isError) R.drawable.warning else R.drawable.success,
                    contentDescription = "Sync status",
                    modifier = Modifier.size(18.dp)
                )
                Text(
                    text = message,
                    color = if (syncState.isError) MaterialTheme.colorScheme.error else OraGold,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Text(text = "WELCOME, $nickname", style = MaterialTheme.typography.titleMedium)

        OraCard(title = "ADVENTURER CARD", iconRes = R.drawable.level) {
            val stats = userStatsState.stats
            Text(
                text = stats?.nickname?.ifBlank { nickname } ?: nickname,
                style = MaterialTheme.typography.titleMedium
            )

            if (userStatsState.isLoading && stats == null) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
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
            } else {
                StatLine(label = "RPG STATS", value = "UNAVAILABLE", iconRes = R.drawable.warning)
            }

            userStatsState.errorMessage?.let { message ->
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        OraCard(title = "LAST ADVENTURE", iconRes = R.drawable.adventure) {
            if (latestActivity == null) {
                Text(text = "NO ADVENTURE YET", style = MaterialTheme.typography.titleMedium)
                StatLine(label = "Start your first adventure.", value = "", iconRes = R.drawable.adventure)
            } else {
                Text(text = formatActivityDateTime(latestActivity.startDateTimeMillis), style = MaterialTheme.typography.titleMedium)
                StatLine(label = "Distance", value = formatDistanceKm(latestActivity.distanceMeters), iconRes = R.drawable.distance)
                StatLine(label = "Duration", value = formatDuration(latestActivity.activeDurationMillis), iconRes = R.drawable.duration)
                StatLine(label = "Pace", value = formatPaceSecondsPerKm(latestActivity.averagePaceSecondsPerKm), iconRes = R.drawable.pace)
            }
        }
    }
}

private fun formatActivityDateTime(epochMillis: Long): String {
    val formatter = DateTimeFormatter.ofPattern("MMM dd - HH:mm", Locale.US)
    return Instant.ofEpochMilli(epochMillis)
        .atZone(ZoneId.systemDefault())
        .format(formatter)
        .uppercase(Locale.US)
}
