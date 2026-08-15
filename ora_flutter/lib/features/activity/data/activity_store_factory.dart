import 'activity_store.dart';
import 'activity_store_factory_native.dart'
    if (dart.library.js_interop) 'activity_store_factory_web.dart';

ActivityStore createActivityStore() => createActivityStoreForPlatform();
