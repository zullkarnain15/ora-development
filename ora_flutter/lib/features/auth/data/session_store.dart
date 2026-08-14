import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/auth_models.dart';

abstract interface class SessionStore {
  Future<UserSession?> load();
  Future<void> save(UserSession session);
  Future<void> clear();
}

class NativeSecureSessionStore implements SessionStore {
  const NativeSecureSessionStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ora/session_store');

  final MethodChannel _channel;
  static const _storageKey = 'active_session_v1';

  @override
  Future<UserSession?> load() async {
    final encoded = await _channel.invokeMethod<String>('read', {
      'key': _storageKey,
    });
    if (encoded == null) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid stored session.');
    }
    return UserSession.fromJson(decoded);
  }

  @override
  Future<void> save(UserSession session) => _channel.invokeMethod<void>(
    'write',
    {'key': _storageKey, 'value': jsonEncode(session.toJson())},
  );

  @override
  Future<void> clear() =>
      _channel.invokeMethod<void>('delete', {'key': _storageKey});
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);
  UserSession? session;

  @override
  Future<UserSession?> load() async => session;

  @override
  Future<void> save(UserSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}
