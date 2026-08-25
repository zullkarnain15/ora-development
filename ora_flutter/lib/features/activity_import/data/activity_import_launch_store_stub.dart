import 'activity_import_launch_store.dart';

ActivityImportLaunchStore createPlatformActivityImportLaunchStore() =>
    _MemoryActivityImportLaunchStore();

class _MemoryActivityImportLaunchStore implements ActivityImportLaunchStore {
  Map<String, Object?>? _value;

  @override
  Future<Map<String, Object?>?> load() async => _value;

  @override
  Future<void> save(Map<String, Object?> value) async {
    _value = Map.unmodifiable(value);
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}
