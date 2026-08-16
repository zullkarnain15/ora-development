import 'gps_soak.dart';
import 'gps_soak_policy_factory_native.dart'
    if (dart.library.js_interop) 'gps_soak_policy_factory_web.dart';

GpsSoakPolicy createGpsSoakPolicy() => createGpsSoakPolicyForPlatform();
