package com.otorunners.ora.ui

import android.app.Activity
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.otorunners.ora.R
import com.otorunners.ora.auth.AuthStage
import com.otorunners.ora.auth.AuthOperation
import com.otorunners.ora.auth.AuthViewModel
import com.otorunners.ora.auth.UserSession
import com.otorunners.ora.data.ActivityHistoryViewModel
import com.otorunners.ora.data.GuildUiState
import com.otorunners.ora.data.GuildViewModel
import com.otorunners.ora.data.LeaderboardUiState
import com.otorunners.ora.data.LeaderboardViewModel
import com.otorunners.ora.data.QuestViewModel
import com.otorunners.ora.data.local.ActivityTotals
import com.otorunners.ora.run.RunViewModel
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.screens.ActivationScreen
import com.otorunners.ora.ui.screens.GuildScreen
import com.otorunners.ora.ui.screens.HomeScreen
import com.otorunners.ora.ui.screens.LoginScreen
import com.otorunners.ora.ui.screens.ProfileScreen
import com.otorunners.ora.ui.screens.QuestScreen
import com.otorunners.ora.ui.screens.RunScreen
import com.otorunners.ora.ui.screens.SettingsScreen
import com.otorunners.ora.ui.theme.OraForest
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraPanel

private enum class OraTab(val label: String, val iconRes: Int) {
    Home("Home", R.drawable.home),
    Quest("Quest", R.drawable.quest),
    Run("RUN", R.drawable.run),
    Guild("Guild", R.drawable.guild),
    You("You", R.drawable.you)
}

private const val EXIT_BACK_PRESS_WINDOW_MS = 2_000L

@Composable
fun OraApp(authViewModel: AuthViewModel = viewModel()) {
    val authState by authViewModel.uiState.collectAsState()

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        when (authState.stage) {
            AuthStage.LOGIN -> LoginScreen(
                errorMessage = authState.errorMessage,
                isLoading = authState.operation == AuthOperation.LOGIN,
                onClearError = authViewModel::clearError,
                onLogin = authViewModel::login
            )
            AuthStage.ACTIVATION -> {
                val pending = authState.pendingActivation
                if (pending != null) {
                    ActivationScreen(
                        divisionGuild = pending.divisionGuild,
                        errorMessage = authState.errorMessage,
                        isLoading = authState.operation == AuthOperation.ACTIVATION,
                        onClearError = authViewModel::clearError,
                        onActivate = authViewModel::activateNickname
                    )
                }
            }
            AuthStage.AUTHENTICATED -> {
                val user = authState.user
                if (user != null) {
                    AuthenticatedOraApp(
                        user = user,
                        onLogout = authViewModel::logout
                    )
                }
            }
        }
    }
}

@Composable
private fun AuthenticatedOraApp(
    user: UserSession,
    onLogout: () -> Unit
) {
    var selectedTab by remember { mutableStateOf(OraTab.Home) }
    var showSettings by remember { mutableStateOf(false) }
    var lastExitBackPressAt by remember { mutableStateOf(0L) }
    val context = LocalContext.current
    val runViewModel: RunViewModel = viewModel()
    val activityHistoryViewModel: ActivityHistoryViewModel = viewModel()
    val questViewModel: QuestViewModel = viewModel()
    val guildViewModel: GuildViewModel = viewModel()
    val leaderboardViewModel: LeaderboardViewModel = viewModel()
    val activitySyncState by activityHistoryViewModel.syncUiState.collectAsState()
    val userStatsState by activityHistoryViewModel.userStatsUiState.collectAsState()
    val questState by questViewModel.uiState.collectAsState()
    val collectedGuildState by guildViewModel.uiState.collectAsState()
    val guildState = collectedGuildState.takeIf { it.ownerNik == user.nik }
        ?: GuildUiState(ownerNik = user.nik, isLoading = true)
    val collectedLeaderboardState by leaderboardViewModel.uiState.collectAsState()
    val leaderboardState = collectedLeaderboardState.takeIf { it.ownerNik == user.nik }
        ?: LeaderboardUiState(ownerNik = user.nik, isLoading = true)
    val latestActivityFlow = remember(user.nik) { activityHistoryViewModel.latestActivity(user.nik) }
    val activitiesFlow = remember(user.nik) { activityHistoryViewModel.activitiesNewestFirst(user.nik) }
    val totalsFlow = remember(user.nik) { activityHistoryViewModel.activityTotals(user.nik) }
    val latestActivity by latestActivityFlow.collectAsState(initial = null)
    val activities by activitiesFlow.collectAsState(initial = emptyList())
    val activityTotals by totalsFlow.collectAsState(
        initial = ActivityTotals(
            activityCount = 0,
            totalDistanceMeters = 0.0,
            totalActiveDurationMillis = 0L
        )
    )

    LaunchedEffect(user) {
        runViewModel.setActiveUser(user)
        activityHistoryViewModel.refreshUserStats(user)
        activityHistoryViewModel.retryPendingSync(user)
    }

    LaunchedEffect(user.nik) {
        runViewModel.autoSyncEvents.collect { event ->
            if (
                event.ownerNik == user.nik &&
                event.failedCount == 0 &&
                event.pendingCount == 0
            ) {
                activityHistoryViewModel.refreshUserStats(user)
            }
        }
    }

    BackHandler {
        if (showSettings) {
            showSettings = false
            return@BackHandler
        }

        val now = System.currentTimeMillis()
        if (now - lastExitBackPressAt <= EXIT_BACK_PRESS_WINDOW_MS) {
            (context as? Activity)?.finish()
        } else {
            lastExitBackPressAt = now
            Toast.makeText(context, "PRESS BACK AGAIN TO EXIT ORA", Toast.LENGTH_SHORT).show()
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            if (!showSettings) {
                NavigationBar(containerColor = OraForest) {
                    OraTab.entries.forEach { tab ->
                        val isRun = tab == OraTab.Run
                        NavigationBarItem(
                            selected = selectedTab == tab,
                            onClick = {
                                selectedTab = tab
                                showSettings = false
                            },
                            icon = {
                                OraIcon(
                                    drawableRes = tab.iconRes,
                                    contentDescription = tab.label,
                                    modifier = Modifier.size(if (isRun) 34.dp else 26.dp)
                                )
                            },
                            label = {
                                Text(
                                    text = tab.label,
                                    fontWeight = if (isRun) FontWeight.Black else FontWeight.SemiBold
                                )
                            },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = OraGold,
                                selectedTextColor = OraGold,
                                indicatorColor = if (isRun) OraGold.copy(alpha = 0.18f) else OraPanel,
                                unselectedIconColor = if (isRun) OraGold else MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = if (isRun) OraGold else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        val modifier = Modifier.padding(innerPadding)
        if (showSettings) {
            SettingsScreen(
                user = user,
                modifier = modifier,
                onBack = { showSettings = false },
                onLogout = {
                    runViewModel.doneSummary()
                    runViewModel.clearActiveUser()
                    onLogout()
                }
            )
        } else {
            when (selectedTab) {
                OraTab.Home -> HomeScreen(
                    nickname = user.nickname,
                    latestActivity = latestActivity,
                    userStatsState = userStatsState,
                    syncState = activitySyncState,
                    modifier = modifier,
                    onSync = {
                        activityHistoryViewModel.manualSync(user) {
                            questViewModel.refresh(user.sessionToken)
                        }
                    }
                )
                OraTab.Quest -> QuestScreen(
                    uiState = questState,
                    onRefresh = { questViewModel.refresh(user.sessionToken) },
                    onClaim = { questId ->
                        questViewModel.claimReward(user.sessionToken, questId) {
                            activityHistoryViewModel.refreshUserStats(user)
                        }
                    },
                    modifier = modifier
                )
                OraTab.Run -> RunScreen(modifier = modifier, runViewModel = runViewModel)
                OraTab.Guild -> GuildScreen(
                    uiState = guildState,
                    leaderboardState = leaderboardState,
                    onRefresh = {
                        guildViewModel.refresh(user.sessionToken, user.nik)
                    },
                    onRefreshBoard = {
                        leaderboardViewModel.refresh(
                            user.sessionToken,
                            user.nik,
                            leaderboardState.scope,
                            leaderboardState.metric
                        )
                    },
                    onSelectBoardScope = { scope ->
                        leaderboardViewModel.refresh(
                            user.sessionToken,
                            user.nik,
                            scope,
                            leaderboardState.metric
                        )
                    },
                    onSelectBoardMetric = { metric ->
                        leaderboardViewModel.refresh(
                            user.sessionToken,
                            user.nik,
                            leaderboardState.scope,
                            metric
                        )
                    },
                    modifier = modifier
                )
                OraTab.You -> ProfileScreen(
                    nickname = user.nickname,
                    divisionGuild = user.divisionGuild,
                    activities = activities,
                    activityTotals = activityTotals,
                    userStatsState = userStatsState,
                    syncState = activitySyncState,
                    onSync = { activityHistoryViewModel.manualSync(user) },
                    onOpenSettings = { showSettings = true },
                    modifier = modifier
                )
            }
        }
    }
}
