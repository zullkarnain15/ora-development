package com.otorunners.ora_flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.location.Location
import android.location.LocationListener
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TrackingBridge(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, METHOD_CHANNEL)
    private val events = EventChannel(messenger, EVENT_CHANNEL)
    private var permissionResult: MethodChannel.Result? = null
    private var previewListener: LocationListener? = null
    private var previewSequence = 0L

    fun configure() {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        stopPreview()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        permissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "requestPermission" && !validContract(call)) {
            result.error("CONTRACT_MISMATCH", "Unsupported tracking contract version.", null)
            return
        }
        when (call.method) {
            "clockSnapshot" -> result.success(clockSnapshot())
            "status" -> result.success(status())
            "requestPermission" -> requestPermission(result)
            "prepare" -> prepare(result)
            "cancelPrepare" -> {
                stopPreview()
                result.success(null)
            }
            "start" -> command(call, result, TrackingService.ACTION_START, foreground = true)
            "pause" -> command(call, result, TrackingService.ACTION_PAUSE)
            "resume" -> command(call, result, TrackingService.ACTION_RESUME)
            "stop" -> command(call, result, TrackingService.ACTION_STOP)
            "acknowledgePendingAction" -> {
                preferences().edit().remove(TrackingService.KEY_PENDING_ACTION).apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun validContract(call: MethodCall): Boolean {
        if (call.method == "acknowledgePendingAction") return true
        return call.argument<Int>("contractVersion") == CONTRACT_VERSION
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("PERMISSION_REQUEST_ACTIVE", "A permission request is already active.", null)
            return
        }
        if (fineLocationGranted() && notificationGranted()) {
            result.success(status())
            return
        }
        permissionResult = result
        val permissions = buildList {
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        activity.requestPermissions(permissions.toTypedArray(), LOCATION_PERMISSION_REQUEST)
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != LOCATION_PERMISSION_REQUEST) return
        permissionResult?.success(status())
        permissionResult = null
    }

    private fun command(
        call: MethodCall,
        result: MethodChannel.Result,
        action: String,
        foreground: Boolean = false
    ) {
        if (action == TrackingService.ACTION_START) stopPreview()
        val sessionId = call.argument<String>("sessionId")
        if (sessionId.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "A run session id is required.", null)
            return
        }
        if ((action == TrackingService.ACTION_START || action == TrackingService.ACTION_RESUME) &&
            !fineLocationGranted()
        ) {
            val code = if (coarseLocationGranted()) {
                "PRECISE_LOCATION_REQUIRED"
            } else {
                "LOCATION_PERMISSION_DENIED"
            }
            result.error(code, "Precise location permission is required.", null)
            return
        }
        if ((action == TrackingService.ACTION_START || action == TrackingService.ACTION_RESUME) &&
            !locationEnabled()
        ) {
            result.error("LOCATION_DISABLED", "Location services are disabled.", null)
            return
        }
        val intent = Intent(activity, TrackingService::class.java)
            .setAction(action)
            .putExtra(TrackingService.EXTRA_SESSION_ID, sessionId)
            .putExtra(
                TrackingService.EXTRA_DIAGNOSTICS_ENABLED,
                call.argument<Boolean>("diagnosticsEnabled") == true
            )
        try {
            if (foreground) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
            result.success(null)
        } catch (_: SecurityException) {
            result.error(
                "FOREGROUND_SERVICE_START_FAILED",
                "Location foreground service could not start with the current permission.",
                null
            )
        } catch (_: RuntimeException) {
            result.error(
                "FOREGROUND_SERVICE_START_FAILED",
                "Start tracking while ORA is visible, then try again.",
                null
            )
        }
    }

    private fun prepare(result: MethodChannel.Result) {
        if (!fineLocationGranted()) {
            result.error("LOCATION_PERMISSION_DENIED", "Precise location permission is required.", null)
            return
        }
        if (!locationEnabled()) {
            result.error("LOCATION_DISABLED", "Location services are disabled.", null)
            return
        }
        if (previewListener != null) {
            result.success(null)
            return
        }
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        previewSequence = 0L
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val received = SystemClock.elapsedRealtime()
                val providerMonotonic = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                    location.elapsedRealtimeNanos / 1_000_000L
                } else received
                TrackingEventBus.emit(mapOf(
                    "contractVersion" to CONTRACT_VERSION,
                    "type" to "location",
                    "sessionId" to "",
                    "sequence" to ++previewSequence,
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracyMeters" to location.accuracy.takeIf { location.hasAccuracy() },
                    "provider" to (location.provider ?: "unknown"),
                    "providerMonotonicMillis" to providerMonotonic,
                    "receivedMonotonicMillis" to received,
                    "epochMillis" to location.time,
                    "isMocked" to location.isFromMockProvider
                ))
            }

            override fun onProviderDisabled(provider: String) {
                TrackingEventBus.emit(mapOf("type" to "providerUnavailable", "code" to "LOCATION_PROVIDER_UNAVAILABLE"))
            }

            @Suppress("DEPRECATION")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
        }
        try {
            previewListener = listener
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 2f, listener, Looper.getMainLooper())
            }
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                manager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000L, 2f, listener, Looper.getMainLooper())
            }
            result.success(null)
        } catch (_: SecurityException) {
            previewListener = null
            result.error("LOCATION_PERMISSION_DENIED", "Precise location permission is required.", null)
        }
    }

    fun stopPreview() {
        val listener = previewListener ?: return
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        manager.removeUpdates(listener)
        previewListener = null
    }

    private fun status(): Map<String, Any?> {
        val prefs = preferences()
        val state = prefs.getString(TrackingService.KEY_TRACKING_STATE, "stopped")
        val lastActive = prefs.getLong(TrackingService.KEY_LAST_ACTIVE_MONOTONIC, 0L)
        val heartbeatFresh = lastActive > 0L &&
            SystemClock.elapsedRealtime() - lastActive <= HEARTBEAT_FRESH_MILLIS
        val serviceActive = prefs.getBoolean(TrackingService.KEY_SERVICE_ACTIVE, false) &&
            (state == "paused" || heartbeatFresh)
        return mapOf(
            "contractVersion" to CONTRACT_VERSION,
            "permission" to when {
                fineLocationGranted() -> "precise"
                coarseLocationGranted() -> "approximate"
                else -> "denied"
            },
            "locationEnabled" to locationEnabled(),
            "serviceActive" to serviceActive,
            "trackingState" to state,
            "lastActiveMonotonicMillis" to lastActive.takeIf { it > 0L },
            "notificationGranted" to notificationGranted(),
            "sessionId" to prefs.getString(TrackingService.KEY_SESSION_ID, null),
            "pendingAction" to prefs.getString(TrackingService.KEY_PENDING_ACTION, null)
        )
    }

    private fun clockSnapshot(): Map<String, Long> {
        val monotonic = SystemClock.elapsedRealtime()
        val epoch = System.currentTimeMillis()
        return mapOf(
            "monotonicMillis" to monotonic,
            "epochMillis" to epoch,
            "bootEpochMillis" to epoch - monotonic
        )
    }

    private fun fineLocationGranted(): Boolean = activity.checkSelfPermission(
        Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    private fun coarseLocationGranted(): Boolean = activity.checkSelfPermission(
        Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    private fun notificationGranted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun locationEnabled(): Boolean {
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    private fun preferences() = activity.getSharedPreferences(
        TrackingService.PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        TrackingEventBus.attach(events)
    }

    override fun onCancel(arguments: Any?) {
        TrackingEventBus.detach()
    }

    companion object {
        const val CONTRACT_VERSION = 1
        const val METHOD_CHANNEL = "ora/tracking/methods/v1"
        const val EVENT_CHANNEL = "ora/tracking/events/v1"
        private const val LOCATION_PERMISSION_REQUEST = 7301
        private const val HEARTBEAT_FRESH_MILLIS = 5_000L
    }
}
