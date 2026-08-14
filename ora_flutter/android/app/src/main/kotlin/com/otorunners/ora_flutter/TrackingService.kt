package com.otorunners.ora_flutter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.pm.ApplicationInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.SystemClock
import android.os.Handler
import android.os.Looper
import android.util.Log

class TrackingService : Service(), LocationListener {
    private lateinit var locationManager: LocationManager
    private var sessionId: String? = null
    private var diagnosticsEnabled = false
    private var sequence = 0L
    private val heartbeatHandler = Handler(Looper.getMainLooper())
    private val heartbeat = object : Runnable {
        override fun run() {
            preferences().edit()
                .putLong(KEY_LAST_ACTIVE_MONOTONIC, SystemClock.elapsedRealtime())
                .apply()
            heartbeatHandler.postDelayed(this, HEARTBEAT_INTERVAL_MILLIS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
        debug("service_on_create")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            restoreAfterSystemRestart()
            return START_STICKY
        }
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: savedSessionId()
        diagnosticsEnabled = intent.getBooleanExtra(EXTRA_DIAGNOSTICS_ENABLED, diagnosticsEnabled)
        val fromNotification = intent.getBooleanExtra(EXTRA_FROM_NOTIFICATION, false)
        when (intent.action) {
            ACTION_START, ACTION_RESUME -> {
                if (fromNotification) savePendingAction("resume")
                promote(paused = false)
                startLocationUpdates()
            }
            ACTION_PAUSE -> {
                if (fromNotification) savePendingAction("pause")
                pauseLocationUpdates()
            }
            ACTION_FINISH -> {
                savePendingAction("finish")
                stopTracking()
            }
            ACTION_STOP -> stopTracking()
            else -> restoreAfterSystemRestart()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onLocationChanged(location: Location) {
        val received = SystemClock.elapsedRealtime()
        sequence += 1
        TrackingEventBus.emit(
            mapOf(
                "contractVersion" to TrackingBridge.CONTRACT_VERSION,
                "type" to "location",
                "sessionId" to sessionId,
                "sequence" to sequence,
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracyMeters" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
                "provider" to (location.provider ?: "unknown"),
                "providerMonotonicMillis" to location.elapsedRealtimeNanos / 1_000_000L,
                "receivedMonotonicMillis" to received,
                "epochMillis" to location.time,
                "isMocked" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    location.isMock
                } else {
                    @Suppress("DEPRECATION")
                    location.isFromMockProvider
                }
            )
        )
        debug(
            "raw_location latency_ms=${received - location.elapsedRealtimeNanos / 1_000_000L} " +
                "accuracy_band=${accuracyBand(location)}"
        )
    }

    override fun onProviderDisabled(provider: String) {
        TrackingEventBus.emit(
            mapOf(
                "contractVersion" to TrackingBridge.CONTRACT_VERSION,
                "type" to "providerUnavailable",
                "code" to "LOCATION_PROVIDER_UNAVAILABLE",
                "message" to "Location provider is disabled."
            )
        )
        debug("provider_disabled provider=$provider")
    }

    override fun onProviderEnabled(provider: String) {
        debug("provider_enabled provider=$provider")
    }

    @Deprecated("Deprecated in Android")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    override fun onDestroy() {
        heartbeatHandler.removeCallbacks(heartbeat)
        locationManager.removeUpdates(this)
        preferences().edit()
            .putBoolean(KEY_SERVICE_ACTIVE, false)
            .putString(KEY_TRACKING_STATE, "stopped")
            .apply()
        TrackingEventBus.emit(mapOf("type" to "serviceState", "state" to "stopped"))
        debug("service_on_destroy")
        super.onDestroy()
    }

    private fun restoreAfterSystemRestart() {
        val prefs = preferences()
        sessionId = prefs.getString(KEY_SESSION_ID, null)
        val state = prefs.getString(KEY_TRACKING_STATE, "stopped")
        if (sessionId == null || !prefs.getBoolean(KEY_SERVICE_ACTIVE, false)) {
            stopSelf()
            return
        }
        if (state == "paused") {
            promote(paused = true)
        } else {
            promote(paused = false)
            startLocationUpdates()
        }
        debug("service_restored state=$state")
    }

    private fun promote(paused: Boolean) {
        val notification = buildNotification(paused)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        preferences().edit()
            .putBoolean(KEY_SERVICE_ACTIVE, true)
            .putString(KEY_SESSION_ID, sessionId)
            .putString(KEY_TRACKING_STATE, if (paused) "paused" else "tracking")
            .apply()
        heartbeatHandler.removeCallbacks(heartbeat)
        if (!paused) {
            heartbeat.run()
        }
        TrackingEventBus.emit(
            mapOf("type" to "serviceState", "state" to if (paused) "paused" else "tracking")
        )
        debug("foreground_promoted state=${if (paused) "paused" else "tracking"}")
    }

    private fun startLocationUpdates() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            emitError("PRECISE_LOCATION_REQUIRED", "Precise location permission is required.")
            stopTracking()
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !locationManager.isLocationEnabled) {
            emitError("LOCATION_DISABLED", "Location services are disabled.")
            stopTracking()
            return
        }
        locationManager.removeUpdates(this)
        var requested = false
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            if (!locationManager.isProviderEnabled(provider)) continue
            try {
                locationManager.requestLocationUpdates(
                    provider,
                    LOCATION_INTERVAL_MILLIS,
                    MIN_DISTANCE_METERS,
                    this
                )
                requested = true
                debug("location_request_success provider=$provider")
            } catch (_: SecurityException) {
                emitError("LOCATION_PERMISSION_DENIED", "Location permission was revoked.")
                stopTracking()
                return
            } catch (_: RuntimeException) {
                debug("location_request_failed provider=$provider")
            }
        }
        if (!requested) {
            emitError("LOCATION_PROVIDER_UNAVAILABLE", "No enabled location provider is available.")
            stopTracking()
        }
    }

    private fun pauseLocationUpdates() {
        locationManager.removeUpdates(this)
        heartbeatHandler.removeCallbacks(heartbeat)
        promote(paused = true)
        debug("tracking_paused")
    }

    private fun stopTracking() {
        locationManager.removeUpdates(this)
        heartbeatHandler.removeCallbacks(heartbeat)
        preferences().edit()
            .putBoolean(KEY_SERVICE_ACTIVE, false)
            .putString(KEY_TRACKING_STATE, "stopped")
            .remove(KEY_SESSION_ID)
            .apply()
        stopForeground(STOP_FOREGROUND_REMOVE)
        TrackingEventBus.emit(mapOf("type" to "serviceState", "state" to "stopped"))
        stopSelf()
    }

    private fun emitError(code: String, message: String) {
        TrackingEventBus.emit(
            mapOf(
                "contractVersion" to TrackingBridge.CONTRACT_VERSION,
                "type" to "error",
                "code" to code,
                "message" to message
            )
        )
        debug("tracking_error code=$code")
    }

    private fun buildNotification(paused: Boolean): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            7302,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val toggleAction = if (paused) ACTION_RESUME else ACTION_PAUSE
        val toggleTitle = if (paused) "Resume" else "Pause"
        val toggleIntent = PendingIntent.getService(
            this,
            7303,
            Intent(this, TrackingService::class.java)
                .setAction(toggleAction)
                .putExtra(EXTRA_SESSION_ID, sessionId)
                .putExtra(EXTRA_FROM_NOTIFICATION, true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val finishIntent = PendingIntent.getService(
            this,
            7304,
            Intent(this, TrackingService::class.java)
                .setAction(ACTION_FINISH)
                .putExtra(EXTRA_SESSION_ID, sessionId)
                .putExtra(EXTRA_FROM_NOTIFICATION, true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("ORA Run Adventure")
            .setContentText(if (paused) "Adventure paused" else "GPS tracking active")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, toggleTitle, toggleIntent).build())
            .addAction(Notification.Action.Builder(null, "Finish", finishIntent).build())
            .build()
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "ORA run tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows controls while an ORA adventure is tracking."
                setShowBadge(false)
            }
        )
    }

    private fun savePendingAction(action: String) {
        preferences().edit().putString(KEY_PENDING_ACTION, action).apply()
    }

    private fun savedSessionId(): String? = preferences().getString(KEY_SESSION_ID, null)

    private fun preferences() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    private fun accuracyBand(location: Location): String = when {
        !location.hasAccuracy() -> "unknown"
        location.accuracy <= 10f -> "excellent"
        location.accuracy <= 20f -> "good"
        location.accuracy <= 30f -> "weak"
        else -> "poor"
    }

    private fun debug(message: String) {
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (diagnosticsEnabled || debuggable) Log.d(LOG_TAG, message)
    }

    companion object {
        const val ACTION_START = "com.otorunners.ora_flutter.tracking.START"
        const val ACTION_PAUSE = "com.otorunners.ora_flutter.tracking.PAUSE"
        const val ACTION_RESUME = "com.otorunners.ora_flutter.tracking.RESUME"
        const val ACTION_FINISH = "com.otorunners.ora_flutter.tracking.FINISH"
        const val ACTION_STOP = "com.otorunners.ora_flutter.tracking.STOP"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_DIAGNOSTICS_ENABLED = "diagnosticsEnabled"
        const val EXTRA_FROM_NOTIFICATION = "fromNotification"

        const val PREFERENCES_NAME = "ora_tracking_native_v1"
        const val KEY_SERVICE_ACTIVE = "serviceActive"
        const val KEY_TRACKING_STATE = "trackingState"
        const val KEY_SESSION_ID = "sessionId"
        const val KEY_PENDING_ACTION = "pendingAction"
        const val KEY_LAST_ACTIVE_MONOTONIC = "lastActiveMonotonicMillis"

        private const val NOTIFICATION_CHANNEL = "ora_run_tracking_v1"
        private const val NOTIFICATION_ID = 7300
        private const val LOCATION_INTERVAL_MILLIS = 1_000L
        private const val MIN_DISTANCE_METERS = 2f
        private const val HEARTBEAT_INTERVAL_MILLIS = 1_000L
        private const val LOG_TAG = "ORA_RUN"
    }
}
