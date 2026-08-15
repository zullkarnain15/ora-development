import 'tracking_models.dart';
import 'tracking_policy_factory_native.dart'
    if (dart.library.js_interop) 'tracking_policy_factory_web.dart';

TrackingPolicy createTrackingPolicy() => createTrackingPolicyForPlatform();
