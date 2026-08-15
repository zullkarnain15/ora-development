import 'native_tracking_adapter.dart';

TrackingNativeAdapter createTrackingAdapterForPlatform() =>
    const MethodChannelTrackingAdapter();
