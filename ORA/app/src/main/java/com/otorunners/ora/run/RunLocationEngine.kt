package com.otorunners.ora.run

import kotlin.math.max
import kotlin.math.min

data class GpsPoint(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float?,
    val elapsedRealtimeNanos: Long
)

enum class LocationDecisionType {
    BASELINE,
    REENTRY_BASELINE,
    ACCEPTED,
    REJECTED,
    IGNORED
}

enum class LocationRejectReason(val diagnosticText: String) {
    NOT_TRACKING("tracking is paused or inactive"),
    INVALID_COORDINATES("invalid coordinates"),
    FUTURE_TIMESTAMP("timestamp is in the future"),
    STALE_LOCATION("stale location"),
    OUT_OF_ORDER("duplicate or out-of-order timestamp"),
    MISSING_ACCURACY("missing accuracy"),
    POOR_ACCURACY("poor accuracy"),
    DUPLICATE_COORDINATE("duplicate coordinate"),
    INVALID_SEGMENT("invalid segment distance"),
    JITTER("movement below jitter threshold"),
    IMPLAUSIBLE_SPEED("implausible running speed")
}

data class LocationDecision(
    val type: LocationDecisionType,
    val reason: LocationRejectReason? = null,
    val segmentMeters: Float = 0f,
    val movementThresholdMeters: Float = 0f,
    val impliedSpeedMetersPerSecond: Float = 0f
)

data class RunLocationDiagnostics(
    val latestAccuracyMeters: Float? = null,
    val acceptedPointsCount: Int = 0,
    val rejectedPointsCount: Int = 0,
    val lastRejectReason: String? = null
)

class RunLocationEngine {
    var totalDistanceMeters: Float = 0f
        private set

    var diagnostics: RunLocationDiagnostics = RunLocationDiagnostics()
        private set

    private var isTracking = false
    private var baseline: GpsPoint? = null
    private var lastProcessedElapsedRealtimeNanos = 0L

    fun startNewSession() {
        totalDistanceMeters = 0f
        diagnostics = RunLocationDiagnostics()
        isTracking = true
        resetBaseline()
    }

    fun pause() {
        isTracking = false
        resetBaseline()
    }

    fun resume() {
        isTracking = true
        resetBaseline()
    }

    fun stop() {
        isTracking = false
        resetBaseline()
    }

    fun reset() {
        totalDistanceMeters = 0f
        diagnostics = RunLocationDiagnostics()
        isTracking = false
        resetBaseline()
    }

    fun process(
        point: GpsPoint,
        nowElapsedRealtimeNanos: Long,
        distanceBetweenMeters: (GpsPoint, GpsPoint) -> Float
    ): LocationDecision {
        if (!isTracking) {
            return LocationDecision(
                type = LocationDecisionType.IGNORED,
                reason = LocationRejectReason.NOT_TRACKING
            )
        }

        diagnostics = diagnostics.copy(latestAccuracyMeters = point.accuracyMeters)

        if (!point.latitude.isFinite() || !point.longitude.isFinite() ||
            point.latitude !in -90.0..90.0 || point.longitude !in -180.0..180.0
        ) {
            return reject(LocationRejectReason.INVALID_COORDINATES)
        }

        val ageNanos = nowElapsedRealtimeNanos - point.elapsedRealtimeNanos
        if (ageNanos < 0L) return reject(LocationRejectReason.FUTURE_TIMESTAMP)
        if (ageNanos > RunTrackingConfig.MAX_LOCATION_AGE_NANOS) {
            return reject(LocationRejectReason.STALE_LOCATION)
        }
        if (point.elapsedRealtimeNanos <= lastProcessedElapsedRealtimeNanos) {
            return reject(LocationRejectReason.OUT_OF_ORDER)
        }
        lastProcessedElapsedRealtimeNanos = point.elapsedRealtimeNanos

        val accuracy = point.accuracyMeters
        if (accuracy == null || !accuracy.isFinite() || accuracy <= 0f) {
            return reject(LocationRejectReason.MISSING_ACCURACY)
        }
        if (accuracy > RunTrackingConfig.MAX_ACCEPTABLE_ACCURACY_METERS) {
            return reject(LocationRejectReason.POOR_ACCURACY)
        }

        val previous = baseline
        if (previous == null) {
            baseline = point
            acceptPoint()
            return LocationDecision(type = LocationDecisionType.BASELINE)
        }

        val elapsedNanos = point.elapsedRealtimeNanos - previous.elapsedRealtimeNanos
        if (elapsedNanos > RunTrackingConfig.GPS_REENTRY_GAP_NANOS) {
            baseline = point
            acceptPoint()
            return LocationDecision(type = LocationDecisionType.REENTRY_BASELINE)
        }

        if (point.latitude == previous.latitude && point.longitude == previous.longitude) {
            // Refresh time at the same position so a stationary user does not look like GPS loss.
            baseline = point
            return reject(LocationRejectReason.DUPLICATE_COORDINATE)
        }

        val segmentMeters = distanceBetweenMeters(previous, point)
        if (!segmentMeters.isFinite() || segmentMeters < 0f) {
            return reject(LocationRejectReason.INVALID_SEGMENT, segmentMeters)
        }

        val elapsedSeconds = elapsedNanos / NANOS_PER_SECOND.toFloat()
        val impliedSpeed = if (elapsedSeconds > 0f) {
            segmentMeters / elapsedSeconds
        } else {
            Float.POSITIVE_INFINITY
        }
        if (!impliedSpeed.isFinite() ||
            impliedSpeed > RunTrackingConfig.MAX_PLAUSIBLE_RUNNING_SPEED_METERS_PER_SECOND
        ) {
            return reject(
                reason = LocationRejectReason.IMPLAUSIBLE_SPEED,
                segmentMeters = segmentMeters,
                impliedSpeedMetersPerSecond = impliedSpeed
            )
        }

        val accuracyThreshold = min(
            RunTrackingConfig.MAX_JITTER_THRESHOLD_METERS,
            (previous.accuracyMeters.orZero() + accuracy) * RunTrackingConfig.ACCURACY_JITTER_FACTOR
        )
        val movementThreshold = max(
            RunTrackingConfig.MIN_SEGMENT_DISTANCE_METERS,
            accuracyThreshold
        )
        if (segmentMeters < movementThreshold) {
            return reject(
                reason = LocationRejectReason.JITTER,
                segmentMeters = segmentMeters,
                movementThresholdMeters = movementThreshold,
                impliedSpeedMetersPerSecond = impliedSpeed
            )
        }

        totalDistanceMeters += segmentMeters
        baseline = point
        acceptPoint()
        return LocationDecision(
            type = LocationDecisionType.ACCEPTED,
            segmentMeters = segmentMeters,
            movementThresholdMeters = movementThreshold,
            impliedSpeedMetersPerSecond = impliedSpeed
        )
    }

    private fun acceptPoint() {
        diagnostics = diagnostics.copy(
            acceptedPointsCount = diagnostics.acceptedPointsCount + 1,
            lastRejectReason = null
        )
    }

    private fun reject(
        reason: LocationRejectReason,
        segmentMeters: Float = 0f,
        movementThresholdMeters: Float = 0f,
        impliedSpeedMetersPerSecond: Float = 0f
    ): LocationDecision {
        diagnostics = diagnostics.copy(
            rejectedPointsCount = diagnostics.rejectedPointsCount + 1,
            lastRejectReason = reason.diagnosticText
        )
        return LocationDecision(
            type = LocationDecisionType.REJECTED,
            reason = reason,
            segmentMeters = segmentMeters,
            movementThresholdMeters = movementThresholdMeters,
            impliedSpeedMetersPerSecond = impliedSpeedMetersPerSecond
        )
    }

    private fun resetBaseline() {
        baseline = null
        lastProcessedElapsedRealtimeNanos = 0L
    }

    private fun Float?.orZero(): Float = this ?: 0f

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000L
    }
}
