package com.otorunners.ora.run

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RunLocationEngineTest {
    @Test
    fun duplicateCoordinate_addsNoDistance() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))

        val result = engine.process(
            point(timestampSeconds = 2),
            now(seconds = 2),
            fixedDistance(50f)
        )

        assertEquals(LocationDecisionType.REJECTED, result.type)
        assertEquals(LocationRejectReason.DUPLICATE_COORDINATE, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun invalidCoordinate_isRejected() {
        val engine = startedEngine()

        val result = engine.process(
            point(latitude = 91.0, timestampSeconds = 1),
            now(seconds = 1),
            fixedDistance(0f)
        )

        assertEquals(LocationRejectReason.INVALID_COORDINATES, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun poorAccuracy_isRejected() {
        val engine = startedEngine()

        val result = engine.process(
            point(accuracyMeters = RunTrackingConfig.MAX_ACCEPTABLE_ACCURACY_METERS + 1f, timestampSeconds = 1),
            now(seconds = 1),
            fixedDistance(0f)
        )

        assertEquals(LocationRejectReason.POOR_ACCURACY, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun stalePoint_isRejected() {
        val engine = startedEngine()

        val result = engine.process(
            point(timestampSeconds = 1),
            now(seconds = 17),
            fixedDistance(0f)
        )

        assertEquals(LocationRejectReason.STALE_LOCATION, result.reason)
    }

    @Test
    fun outOfOrderPoint_isRejected() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 2), now(seconds = 2), fixedDistance(0f))

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.001, timestampSeconds = 1),
            now(seconds = 2),
            fixedDistance(3f)
        )

        assertEquals(LocationRejectReason.OUT_OF_ORDER, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun implausibleSpeedJump_isRejected() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.001, timestampSeconds = 2),
            now(seconds = 2),
            fixedDistance(100f)
        )

        assertEquals(LocationRejectReason.IMPLAUSIBLE_SPEED, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun stationaryJitter_belowDynamicThresholdAddsNoDistance() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.00001, timestampSeconds = 2),
            now(seconds = 2),
            fixedDistance(1.5f)
        )

        assertEquals(LocationRejectReason.JITTER, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun firstValidPointAfterLongGpsGap_isReentryBaseline() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.01, timestampSeconds = 12),
            now(seconds = 12),
            fixedDistance(1_000f)
        )

        assertEquals(LocationDecisionType.REENTRY_BASELINE, result.type)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun firstPointAfterResume_isBaseline() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))
        engine.process(
            point(latitude = BASE_LATITUDE + 0.0001, timestampSeconds = 2),
            now(seconds = 2),
            fixedDistance(3f)
        )
        engine.pause()
        engine.resume()

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.01, timestampSeconds = 4),
            now(seconds = 4),
            fixedDistance(500f)
        )

        assertEquals(LocationDecisionType.BASELINE, result.type)
        assertEquals(3f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun movementDuringPause_addsNoDistance() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))
        engine.pause()

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.01, timestampSeconds = 2),
            now(seconds = 2),
            fixedDistance(500f)
        )

        assertEquals(LocationDecisionType.IGNORED, result.type)
        assertEquals(LocationRejectReason.NOT_TRACKING, result.reason)
        assertEquals(0f, engine.totalDistanceMeters, 0f)
    }

    @Test
    fun validConsecutivePoints_accumulateAndroidProvidedSegment() {
        val engine = startedEngine()
        engine.process(point(timestampSeconds = 1), now(seconds = 1), fixedDistance(0f))

        val result = engine.process(
            point(latitude = BASE_LATITUDE + 0.0001, timestampSeconds = 2),
            now(seconds = 2),
            fixedDistance(3f)
        )

        assertEquals(LocationDecisionType.ACCEPTED, result.type)
        assertEquals(3f, engine.totalDistanceMeters, 0f)
        assertTrue(engine.diagnostics.acceptedPointsCount >= 2)
    }

    private fun startedEngine() = RunLocationEngine().apply { startNewSession() }

    private fun point(
        latitude: Double = BASE_LATITUDE,
        longitude: Double = BASE_LONGITUDE,
        accuracyMeters: Float = 5f,
        timestampSeconds: Long
    ) = GpsPoint(
        latitude = latitude,
        longitude = longitude,
        accuracyMeters = accuracyMeters,
        elapsedRealtimeNanos = now(timestampSeconds)
    )

    private fun fixedDistance(distanceMeters: Float): (GpsPoint, GpsPoint) -> Float = { _, _ -> distanceMeters }

    private fun now(seconds: Long): Long = seconds * NANOS_PER_SECOND

    private companion object {
        const val BASE_LATITUDE = -6.2
        const val BASE_LONGITUDE = 106.8
        const val NANOS_PER_SECOND = 1_000_000_000L
    }
}
