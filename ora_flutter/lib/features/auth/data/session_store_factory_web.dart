import 'package:web/web.dart' as web;

import 'session_store.dart';
import 'web_session_store.dart';

SessionStore createSessionStoreForPlatform() =>
    const WebSessionStore(storage: BrowserWebSessionStorage());

class BrowserWebSessionStorage implements WebSessionStorage {
  const BrowserWebSessionStorage();

  @override
  String? readPersistent(String key) => web.window.localStorage.getItem(key);

  @override
  String? readPerTab(String key) => web.window.sessionStorage.getItem(key);

  @override
  void writePersistent(String key, String value) =>
      web.window.localStorage.setItem(key, value);

  @override
  void removePersistent(String key) => web.window.localStorage.removeItem(key);

  @override
  void removePerTab(String key) => web.window.sessionStorage.removeItem(key);
}
