import 'tracking_models.dart';

/// Conservative browser profile: favor rejecting uncertain fixes over adding
/// false mileage. Centralized here so real-device PWA tuning remains isolated.
const webTrackingPolicy = TrackingPolicy(
  version: 3,
  maxAccuracyMeters: 35,
  minSegmentMeters: 3,
  maxJitterMeters: 8,
  accuracyJitterFactor: .35,
  maxSpeedMetersPerSecond: 10,
  maxLocationAgeMillis: 30000,
  reentryGapMillis: 15000,
  minimumPaceDistanceMeters: 30,
);

TrackingPolicy createTrackingPolicyForPlatform() => webTrackingPolicy;
