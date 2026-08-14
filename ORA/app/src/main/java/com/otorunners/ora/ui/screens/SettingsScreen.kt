package com.otorunners.ora.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.otorunners.ora.R
import com.otorunners.ora.auth.UserSession
import com.otorunners.ora.ui.components.OraCard
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.OraScreenTitle
import com.otorunners.ora.ui.theme.OraCreamMuted
import com.otorunners.ora.ui.theme.OraDisplaySmall
import com.otorunners.ora.ui.theme.OraGold

@Composable
fun SettingsScreen(
    user: UserSession,
    onBack: () -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier
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
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top
        ) {
            TextButton(onClick = onBack) {
                Text(text = "BACK", fontWeight = FontWeight.Bold)
            }
            OraScreenTitle(
                title = "SETTINGS",
                subtitle = "ORA - OTO RUNNERS ADVENTURE",
                iconRes = R.drawable.settings,
                modifier = Modifier.weight(1f)
            )
        }

        OraCard(title = "ACCOUNT", iconRes = R.drawable.you) {
            SettingsInfoRow(iconRes = R.drawable.you, label = "Nickname", value = user.nickname)
            SettingsInfoRow(iconRes = R.drawable.guild, label = "Division / Guild", value = user.divisionGuild)
            SettingsInfoRow(
                iconRes = R.drawable.success,
                label = "Account Status",
                value = if (user.active) "ACTIVE" else "INACTIVE"
            )
            TextButton(onClick = onLogout, modifier = Modifier.align(Alignment.End)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OraIcon(
                        drawableRes = R.drawable.lock,
                        contentDescription = "Logout",
                        modifier = Modifier.size(22.dp)
                    )
                    Text(text = "LOGOUT", fontWeight = FontWeight.Bold)
                }
            }
        }

        OraCard(title = "RUN SETTINGS", iconRes = R.drawable.location) {
            SettingsInfoRow(
                iconRes = R.drawable.location,
                label = "Location / GPS",
                value = "Required during running activity"
            )
            SettingsInfoRow(
                iconRes = R.drawable.lock,
                label = "Tracking Mode",
                value = "Active run continues with the tracking notification"
            )
        }

        OraCard(title = "DATA & SAFETY", iconRes = R.drawable.lock) {
            SettingsInfoRow(
                iconRes = R.drawable.lock,
                label = "Local Session",
                value = "Keeps you signed in on this device"
            )
            SettingsInfoRow(
                iconRes = R.drawable.location,
                label = "Location Information",
                value = "Location is used only when running activity is active"
            )
            SettingsInfoRow(
                iconRes = R.drawable.success,
                label = "Backend",
                value = "Connected to ORA live data"
            )
        }

        OraCard(title = "ABOUT", iconRes = R.drawable.adventure) {
            SettingsInfoRow(iconRes = R.drawable.adventure, label = "ORA", value = "OTO RUNNERS ADVENTURE")
            SettingsInfoRow(iconRes = R.drawable.run, label = "Program", value = "RPG - Run Playing Game")
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "Community",
                    color = OraCreamMuted,
                    style = MaterialTheme.typography.bodyMedium
                )
                Image(
                    painter = painterResource(id = R.drawable.oto_runners),
                    contentDescription = "OTO Runners community",
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                    alignment = Alignment.CenterStart,
                    contentScale = ContentScale.Fit
                )
            }
            SettingsInfoRow(iconRes = R.drawable.success, label = "Version", value = "0.1.0 Tester")
            Text(
                text = "Every Run is an Adventure.",
                color = OraGold,
                style = OraDisplaySmall
            )
        }
    }
}

@Composable
private fun SettingsInfoRow(iconRes: Int, label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(24.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text = label, color = OraCreamMuted, style = MaterialTheme.typography.labelSmall)
            Text(text = value, color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.SemiBold)
        }
    }
}
