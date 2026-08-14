package com.otorunners.ora.ui.screens

import android.Manifest
import android.os.Build
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.otorunners.ora.R
import com.otorunners.ora.run.ActivitySaveStatus
import com.otorunners.ora.run.RunSessionUiState
import com.otorunners.ora.run.RunStatus
import com.otorunners.ora.run.RunViewModel
import com.otorunners.ora.run.formatAveragePace
import com.otorunners.ora.run.formatDistanceKm
import com.otorunners.ora.run.formatDuration
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.PixelBadge
import com.otorunners.ora.ui.theme.OraDisplayLarge
import com.otorunners.ora.ui.theme.OraDisplayMedium
import com.otorunners.ora.ui.theme.OraForestDeep
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraOutline
import com.otorunners.ora.ui.theme.OraOrange
import com.otorunners.ora.ui.theme.OraPanel
import com.otorunners.ora.ui.theme.OraPanelAlt
import com.otorunners.ora.ui.theme.OraSuccess

@Composable
fun RunScreen(modifier: Modifier = Modifier, runViewModel: RunViewModel = viewModel()) {
    val context = LocalContext.current
    val uiState by runViewModel.uiState.collectAsState()
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
        onResult = { permissions ->
            val notificationGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                permissions[Manifest.permission.POST_NOTIFICATIONS] == true ||
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            when {
                permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true && notificationGranted -> {
                    runViewModel.startAdventure()
                }
                permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true -> {
                    runViewModel.reportPreciseLocationRequired()
                }
                permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true -> {
                    runViewModel.reportNotificationPermissionRequired()
                }
                else -> {
                    runViewModel.reportPermissionDenied()
                }
            }
        }
    )

    fun startWithPermission() {
        val permission = Manifest.permission.ACCESS_FINE_LOCATION
        val granted = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        val notificationGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        if (granted && notificationGranted) {
            runViewModel.startAdventure()
        } else {
            val permissions = buildList {
                add(Manifest.permission.ACCESS_COARSE_LOCATION)
                add(Manifest.permission.ACCESS_FINE_LOCATION)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    add(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
            permissionLauncher.launch(permissions.toTypedArray())
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OraIcon(drawableRes = R.drawable.run, contentDescription = "Run Adventure", modifier = Modifier.size(54.dp))
            Text(text = "RUN ADVENTURE", style = OraDisplayLarge, textAlign = TextAlign.Center)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OraIcon(
                    drawableRes = if (uiState.isWarning) R.drawable.warning else R.drawable.location,
                    contentDescription = "Location status",
                    modifier = Modifier.size(22.dp)
                )
                PixelBadge(text = uiState.message.uppercase(), color = if (uiState.isWarning) OraOrange else OraSuccess)
            }
            if (uiState.isBackgroundTracking) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OraIcon(
                        drawableRes = R.drawable.lock,
                        contentDescription = "Background tracking",
                        modifier = Modifier.size(20.dp)
                    )
                    PixelBadge(text = "BACKGROUND TRACKING ACTIVE", color = OraGold)
                }
            }
        }

        RunPanel(uiState = uiState)

        RunActions(
            uiState = uiState,
            onStart = ::startWithPermission,
            onPause = runViewModel::pauseAdventure,
            onResume = runViewModel::resumeAdventure,
            onFinish = runViewModel::finishAdventure,
            onDone = runViewModel::doneSummary
        )
    }
}

@Composable
private fun RunPanel(uiState: RunSessionUiState) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(5.dp),
        color = OraPanel,
        border = BorderStroke(1.5.dp, OraOutline)
    ) {
        if (uiState.status == RunStatus.FINISHED) {
            ResultSummary(uiState = uiState)
        } else {
            Column(
                modifier = Modifier.padding(vertical = 34.dp, horizontal = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(22.dp)
            ) {
                RunMetric(
                    value = formatDistanceKm(uiState.distanceMeters),
                    label = "DISTANCE",
                    valueSize = 56,
                    iconRes = R.drawable.distance
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    RunMetric(
                        value = formatDuration(uiState.activeDurationMillis),
                        label = "DURATION",
                        valueSize = 28,
                        iconRes = R.drawable.duration,
                        modifier = Modifier.weight(1f)
                    )
                    RunMetric(
                        value = formatAveragePace(uiState.activeDurationMillis, uiState.distanceMeters),
                        label = "PACE",
                        valueSize = 28,
                        iconRes = R.drawable.pace,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun ResultSummary(uiState: RunSessionUiState) {
    val summary = uiState.summary
    Column(
        modifier = Modifier.padding(vertical = 28.dp, horizontal = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        OraIcon(drawableRes = R.drawable.success, contentDescription = "Adventure complete", modifier = Modifier.size(42.dp))
        Text(text = "ADVENTURE COMPLETE", style = OraDisplayMedium, color = OraGold, textAlign = TextAlign.Center)
        RunMetric(
            value = formatDistanceKm(summary?.distanceMeters ?: uiState.distanceMeters),
            label = "DISTANCE",
            valueSize = 42,
            iconRes = R.drawable.distance
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            RunMetric(
                value = formatDuration(summary?.durationMillis ?: uiState.activeDurationMillis),
                label = "DURATION",
                valueSize = 24,
                iconRes = R.drawable.duration,
                modifier = Modifier.weight(1f)
            )
            RunMetric(
                value = formatAveragePace(
                    summary?.durationMillis ?: uiState.activeDurationMillis,
                    summary?.distanceMeters ?: uiState.distanceMeters
                ),
                label = "AVG PACE",
                valueSize = 24,
                iconRes = R.drawable.pace,
                modifier = Modifier.weight(1f)
            )
        }
        if (summary?.saveMessage != null) {
            val isFailed = summary.saveStatus == ActivitySaveStatus.FAILED
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OraIcon(
                    drawableRes = if (isFailed) R.drawable.warning else R.drawable.success,
                    contentDescription = summary.saveMessage,
                    modifier = Modifier.size(22.dp)
                )
                PixelBadge(
                    text = summary.saveMessage,
                    color = if (isFailed) OraOrange else OraSuccess
                )
            }
        }
    }
}

@Composable
private fun RunMetric(value: String, label: String, valueSize: Int, iconRes: Int, modifier: Modifier = Modifier) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(26.dp))
        Spacer(modifier = Modifier.height(6.dp))
        Text(text = value, fontSize = valueSize.sp, fontWeight = FontWeight.Black, lineHeight = valueSize.sp)
        Spacer(modifier = Modifier.height(6.dp))
        Text(text = label, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun RunActions(
    uiState: RunSessionUiState,
    onStart: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    onDone: () -> Unit
) {
    when (uiState.status) {
        RunStatus.IDLE -> PrimaryRunButton(label = "START ADVENTURE", iconRes = R.drawable.run, onClick = onStart)
        RunStatus.TRACKING -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            SecondaryRunButton(label = "PAUSE", iconRes = R.drawable.pause, onClick = onPause, modifier = Modifier.weight(1f))
            PrimaryRunButton(label = "FINISH", iconRes = R.drawable.finish, onClick = onFinish, modifier = Modifier.weight(1f))
        }
        RunStatus.PAUSED -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            PrimaryRunButton(label = "RESUME", iconRes = R.drawable.resume, onClick = onResume, modifier = Modifier.weight(1f))
            SecondaryRunButton(label = "FINISH", iconRes = R.drawable.finish, onClick = onFinish, modifier = Modifier.weight(1f))
        }
        RunStatus.FINISHED -> PrimaryRunButton(label = "DONE", iconRes = R.drawable.success, onClick = onDone)
    }
}

@Composable
private fun PrimaryRunButton(label: String, iconRes: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Button(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .height(64.dp),
        shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.buttonColors(containerColor = OraGold, contentColor = OraForestDeep)
    ) {
        ButtonContent(label = label, iconRes = iconRes)
    }
}

@Composable
private fun SecondaryRunButton(label: String, iconRes: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Button(
        onClick = onClick,
        modifier = modifier.height(64.dp),
        shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.buttonColors(containerColor = OraPanelAlt, contentColor = MaterialTheme.colorScheme.onSurface),
        border = BorderStroke(1.dp, OraOutline)
    ) {
        ButtonContent(label = label, iconRes = iconRes)
    }
}

@Composable
private fun ButtonContent(label: String, iconRes: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(26.dp))
        Text(text = label, style = OraDisplayMedium)
    }
}
