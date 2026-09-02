import 'feature_cache_store.dart';
import 'feature_cache_store_factory_native.dart'
    if (dart.library.js_interop) 'feature_cache_store_factory_web.dart';

FeatureCacheStore createFeatureCacheStore() =>
    JsonFeatureCacheStore(storage: createFeatureCacheStorageForPlatform());
