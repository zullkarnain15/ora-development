package com.otorunners.ora.run

import org.junit.Assert.assertEquals
import org.junit.Test

class RunPaceTest {
    @Test
    fun oneKilometerInSixMinutes_isSixMinutePace() {
        assertEquals("06:00 /KM", formatAveragePace(6 * 60 * 1_000L, 1_000f))
    }

    @Test
    fun fiveKilometersInThirtyMinutes_isSixMinutePace() {
        assertEquals("06:00 /KM", formatAveragePace(30 * 60 * 1_000L, 5_000f))
    }

    @Test
    fun tenKilometersInFiftyFiveMinutes_isFiveThirtyPace() {
        assertEquals("05:30 /KM", formatAveragePace(55 * 60 * 1_000L, 10_000f))
    }

    @Test
    fun zeroDistance_hasNoPace() {
        assertEquals("--:-- /KM", formatAveragePace(6 * 60 * 1_000L, 0f))
    }

    @Test
    fun verySmallDistance_hasNoUnstablePace() {
        assertEquals("--:-- /KM", formatAveragePace(10_000L, 5f))
    }

    @Test
    fun nonFiniteDistance_hasNoPace() {
        assertEquals("--:-- /KM", formatAveragePace(10_000L, Float.NaN))
        assertEquals("--:-- /KM", formatAveragePace(10_000L, Float.POSITIVE_INFINITY))
    }

    @Test
    fun defaultRunState_isNotBackgroundTracking() {
        assertEquals(false, RunSessionUiState().isBackgroundTracking)
    }

    @Test
    fun trackingRunState_canExposeBackgroundTrackingActive() {
        val state = RunSessionUiState(
            status = RunStatus.TRACKING,
            distanceMeters = 1_234f,
            activeDurationMillis = 9 * 60 * 1_000L,
            isBackgroundTracking = true
        )

        assertEquals(RunStatus.TRACKING, state.status)
        assertEquals(true, state.isBackgroundTracking)
        assertEquals("1.23 KM", formatDistanceKm(state.distanceMeters))
    }
}
