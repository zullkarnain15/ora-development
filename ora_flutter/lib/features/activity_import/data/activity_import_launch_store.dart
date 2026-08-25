import 'activity_import_launch_store_stub.dart'
    if (dart.library.js_interop) 'activity_import_launch_store_web.dart';

abstract interface class ActivityImportLaunchStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> value);
  Future<void> clear();
}

ActivityImportLaunchStore createActivityImportLaunchStore() =>
    createPlatformActivityImportLaunchStore();
