package com.otorunners.ora.run

object RunTrackingConfig {
    // One-second updates capture normal running cadence without excessive GPS polling.
    const val LOCATION_UPDATE_INTERVAL_MILLIS = 1_000L
    const val MIN_LOCATION_UPDATE_INTERVAL_MILLIS = 1_000L
    const val MIN_LOCATION_UPDATE_DISTANCE_METERS = 2f

    // Outdoor fixes worse than 30 m are too uncertain for run-distance accumulation.
    const val MAX_ACCEPTABLE_ACCURACY_METERS = 30f

    // A 2-5 m accuracy-aware deadband suppresses stationary drift while allowing
    // slow walking to accumulate against the last accepted baseline.
    const val MIN_SEGMENT_DISTANCE_METERS = 2f
    const val MAX_JITTER_THRESHOLD_METERS = 5f
    const val ACCURACY_JITTER_FACTOR = 0.25f

    // 12 m/s (43.2 km/h) leaves headroom for elite sprinting but rejects GPS jumps.
    const val MAX_PLAUSIBLE_RUNNING_SPEED_METERS_PER_SECOND = 12f

    const val MAX_LOCATION_AGE_NANOS = 15_000_000_000L

    // After more than 10 seconds without a valid fix, the next point is a new
    // baseline so a straight-line GPS jump is not added to the run.
    const val GPS_REENTRY_GAP_NANOS = 10_000_000_000L

    // Pace is intentionally unavailable until enough distance exists to be stable.
    const val MIN_PACE_DISTANCE_METERS = 20f
}
