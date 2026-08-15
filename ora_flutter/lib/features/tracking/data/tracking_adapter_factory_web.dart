import 'browser_tracking_capabilities.dart';
import 'native_tracking_adapter.dart';
import 'web_tracking_adapter.dart';

TrackingNativeAdapter createTrackingAdapterForPlatform() => WebTrackingAdapter(
  positionSource: BrowserPositionSource(),
  clock: BrowserTrackingClock(),
  wakeLock: BrowserWakeLock(),
);
