import 'native_tracking_adapter.dart';
import 'tracking_adapter_factory_native.dart'
    if (dart.library.js_interop) 'tracking_adapter_factory_web.dart';

TrackingNativeAdapter createTrackingAdapter() =>
    createTrackingAdapterForPlatform();
