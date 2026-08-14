package com.otorunners.ora.run

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.otorunners.ora.MainActivity
import com.otorunners.ora.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class RunTrackingService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var notificationJob: Job? = null
    private var startedInForeground = false

    override fun onCreate() {
        super.onCreate()
        RunSessionController.configure(applicationContext)
        createNotificationChannel()
        notificationJob = serviceScope.launch {
            RunSessionController.uiState.collectLatest { state ->
                if (startedInForeground && state.status != RunStatus.IDLE && state.status != RunStatus.FINISHED) {
                    notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                ensureForeground()
                RunSessionController.startAdventure(applicationContext)
            }
            ACTION_PAUSE -> {
                ensureForeground()
                RunSessionController.pauseAdventure()
            }
            ACTION_RESUME -> {
                ensureForeground()
                RunSessionController.resumeAdventure(applicationContext)
            }
            ACTION_FINISH -> {
                RunSessionController.finishAdventure()
                stopForegroundAndSelf()
            }
            ACTION_STOP_AND_RESET -> {
                RunSessionController.doneSummary()
                stopForegroundAndSelf()
            }
            else -> {
                if (RunSessionController.uiState.value.status == RunStatus.TRACKING ||
                    RunSessionController.uiState.value.status == RunStatus.PAUSED
                ) {
                    ensureForeground()
                } else {
                    stopSelf(startId)
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        notificationJob?.cancel()
        super.onDestroy()
    }

    private fun ensureForeground() {
        if (startedInForeground) return

        val notification = buildNotification(RunSessionController.uiState.value)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        startedInForeground = true
    }

    private fun stopForegroundAndSelf() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        startedInForeground = false
        stopSelf()
    }

    private fun buildNotification(state: RunSessionUiState): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ora_run)
            .setContentTitle("ORA - Adventure in Progress")
            .setContentText("${formatDistanceKm(state.distanceMeters)} • ${formatDuration(state.activeDurationMillis)}")
            .setSubText(state.status.name)
            .setContentIntent(openAppPendingIntent())
            .setOngoing(state.status == RunStatus.TRACKING || state.status == RunStatus.PAUSED)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        when (state.status) {
            RunStatus.TRACKING -> {
                builder.addAction(notificationAction(R.drawable.pause, "PAUSE", ACTION_PAUSE))
                builder.addAction(notificationAction(R.drawable.finish, "FINISH", ACTION_FINISH))
            }
            RunStatus.PAUSED -> {
                builder.addAction(notificationAction(R.drawable.resume, "RESUME", ACTION_RESUME))
                builder.addAction(notificationAction(R.drawable.finish, "FINISH", ACTION_FINISH))
            }
            else -> Unit
        }

        return builder.build()
    }

    private fun notificationAction(iconRes: Int, title: String, action: String): NotificationCompat.Action {
        val intent = Intent(this, RunTrackingService::class.java).setAction(action)
        val pendingIntent = PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Action.Builder(iconRes, title, pendingIntent).build()
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            OPEN_APP_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps ORA run tracking active while the screen is off."
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private val notificationManager: NotificationManager
        get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        const val ACTION_START = "com.otorunners.ora.run.action.START"
        const val ACTION_PAUSE = "com.otorunners.ora.run.action.PAUSE"
        const val ACTION_RESUME = "com.otorunners.ora.run.action.RESUME"
        const val ACTION_FINISH = "com.otorunners.ora.run.action.FINISH"
        const val ACTION_STOP_AND_RESET = "com.otorunners.ora.run.action.STOP_AND_RESET"

        const val CHANNEL_ID = "ora_run_tracking"
        private const val CHANNEL_NAME = "ORA Run Tracking"
        private const val NOTIFICATION_ID = 4101
        private const val OPEN_APP_REQUEST_CODE = 4102
    }
}
