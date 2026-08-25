import 'dart:convert';

import 'package:web/web.dart' as web;

import 'activity_import_launch_store.dart';

ActivityImportLaunchStore createPlatformActivityImportLaunchStore() =>
    _WebActivityImportLaunchStore();

class _WebActivityImportLaunchStore implements ActivityImportLaunchStore {
  static const _key = 'ora_pending_activity_import';

  @override
  Future<Map<String, Object?>?> load() async {
    final encoded = web.window.sessionStorage.getItem(_key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Object?> value) async {
    web.window.sessionStorage.setItem(_key, jsonEncode(value));
  }

  @override
  Future<void> clear() async {
    web.window.sessionStorage.removeItem(_key);
  }
}
