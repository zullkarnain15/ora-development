import 'package:flutter/services.dart';

import 'feature_cache_store.dart';

FeatureCacheStorage createFeatureCacheStorageForPlatform() =>
    const NativeFeatureCacheStorage();

class NativeFeatureCacheStorage implements FeatureCacheStorage {
  const NativeFeatureCacheStorage({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ora/session_store');

  final MethodChannel _channel;

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> remove(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key});
}
