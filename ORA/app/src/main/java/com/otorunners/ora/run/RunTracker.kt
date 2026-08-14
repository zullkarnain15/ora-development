package com.otorunners.ora.run

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

class RunTracker(
    context: Context,
    private val onLocation: (Location) -> Unit,
    private val onLocationUnavailable: () -> Unit,
    private val onTrackingError: (String) -> Unit
) {
    private val fusedLocationClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context.applicationContext)

    private val locationRequest = LocationRequest.Builder(
        Priority.PRIORITY_HIGH_ACCURACY,
        RunTrackingConfig.LOCATION_UPDATE_INTERVAL_MILLIS
    )
        .setMinUpdateIntervalMillis(RunTrackingConfig.MIN_LOCATION_UPDATE_INTERVAL_MILLIS)
        .setMinUpdateDistanceMeters(RunTrackingConfig.MIN_LOCATION_UPDATE_DISTANCE_METERS)
        .setWaitForAccurateLocation(false)
        .build()

    private var trackingGeneration = 0L
    private var activeCallback: LocationCallback? = null

    @SuppressLint("MissingPermission")
    fun start() {
        if (activeCallback != null) return

        val generation = ++trackingGeneration
        val callback = object : LocationCallback() {
            override fun onLocationAvailability(availability: LocationAvailability) {
                if (isActive(generation, this) && !availability.isLocationAvailable) {
                    onLocationUnavailable()
                } else if (!isActive(generation, this)) {
                    RunDiagnostics.debug {
                        "REJECT callback | reason=inactive callback generation | generation=$generation"
                    }
                }
            }

            override fun onLocationResult(result: LocationResult) {
                if (isActive(generation, this)) {
                    result.locations.forEach(onLocation)
                } else {
                    RunDiagnostics.debug {
                        "REJECT callback | reason=inactive callback generation | generation=$generation"
                    }
                }
            }
        }
        activeCallback = callback

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                callback,
                Looper.getMainLooper()
            ).addOnFailureListener { exception ->
                if (isActive(generation, callback)) {
                    activeCallback = null
                    onTrackingError(
                        if (exception is SecurityException) {
                            "Location permission is required to start an adventure."
                        } else {
                            "Location tracking is not available right now."
                        }
                    )
                }
            }
        } catch (securityException: SecurityException) {
            if (isActive(generation, callback)) {
                activeCallback = null
                onTrackingError("Location permission is required to start an adventure.")
            }
        } catch (exception: RuntimeException) {
            if (isActive(generation, callback)) {
                activeCallback = null
                onTrackingError("Location tracking is not available right now.")
            }
        }
    }

    fun stop() {
        trackingGeneration++
        val callback = activeCallback ?: return
        activeCallback = null
        fusedLocationClient.removeLocationUpdates(callback)
    }

    private fun isActive(generation: Long, callback: LocationCallback): Boolean {
        return trackingGeneration == generation && activeCallback === callback
    }
}
