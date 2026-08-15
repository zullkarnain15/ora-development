import 'dart:convert';

import '../domain/auth_models.dart';
import 'session_store.dart';

abstract interface class WebSessionStorage {
  String? readPersistent(String key);
  String? readPerTab(String key);
  void writePersistent(String key, String value);
  void removePersistent(String key);
  void removePerTab(String key);
}

/// Persists only the backend-issued session until logout or its TTL expires.
/// PINs and backend credentials are never written here. As with any browser
/// token, same-origin script can read it, so the backend remains responsible
/// for authorization and expiry enforcement.
class WebSessionStore implements SessionStore {
  const WebSessionStore({required this.storage});

  static const storageKey = 'ora.active_session_v1';
  final WebSessionStorage storage;

  @override
  Future<UserSession?> load() async {
    try {
      final persistent = storage.readPersistent(storageKey);
      final legacyPerTab = storage.readPerTab(storageKey);
      final encoded = persistent ?? legacyPerTab;
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid session.');
      final session = UserSession.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (persistent == null) {
        storage.writePersistent(storageKey, encoded);
        storage.removePerTab(storageKey);
      }
      return session;
    } on Object {
      _removeStoredSession();
      return null;
    }
  }

  @override
  Future<void> save(UserSession session) async {
    try {
      storage.writePersistent(storageKey, jsonEncode(session.toJson()));
      storage.removePerTab(storageKey);
    } on Object {
      // Authentication remains usable when browser persistence is disabled.
    }
  }

  @override
  Future<void> clear() async {
    _removeStoredSession();
  }

  void _removeStoredSession() {
    try {
      storage.removePersistent(storageKey);
    } on Object {
      // Storage can be unavailable by browser policy.
    }
    try {
      storage.removePerTab(storageKey);
    } on Object {
      // Storage can be unavailable by browser policy.
    }
  }
}
