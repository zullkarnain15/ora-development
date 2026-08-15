import 'session_store.dart';
import 'session_store_factory_native.dart'
    if (dart.library.js_interop) 'session_store_factory_web.dart';

SessionStore createSessionStore() => createSessionStoreForPlatform();
