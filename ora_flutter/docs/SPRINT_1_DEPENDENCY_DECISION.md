# Sprint 1 Dependency Decision - Session Storage

## Decision

ORA uses the `SessionStore` interface with a dependency-free native secure-storage bridge:

- Android: AES-256/GCM data encrypted with an app key held by Android Keystore. The encrypted payload is stored in private SharedPreferences. Android backup is disabled.
- iOS: Generic Password item in Keychain with `WhenUnlockedThisDeviceOnly` accessibility.
- Dart: only serialized session JSON crosses the private method channel. Tokens and payloads are never logged.

## Why

The first evaluated option was `flutter_secure_storage`. It was removed before implementation because its plugin setup required Windows symlink/Developer Mode support on the current build host. A small native bridge provides the required security properties without a runtime package or workstation-specific plugin setup.

The storage format is versioned by the Dart key `active_session_v1`. Malformed, undecryptable, inactive, or expired sessions are deleted and treated as signed out.

## Scope

This bridge stores only the authenticated ORA session. It does not provide general application preferences and must not be used for run history or tracking data.
