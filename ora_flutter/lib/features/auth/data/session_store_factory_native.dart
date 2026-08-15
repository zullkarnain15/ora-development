import 'session_store.dart';

SessionStore createSessionStoreForPlatform() =>
    const NativeSecureSessionStore();
