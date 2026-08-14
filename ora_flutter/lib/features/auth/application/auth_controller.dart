import 'package:flutter/foundation.dart';

import '../domain/auth_models.dart';
import 'auth_repository.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.repository);
  final AuthRepository repository;

  AuthStage stage = AuthStage.restoring;
  AuthOperation? operation;
  UserSession? session;
  PendingActivation? pendingActivation;
  String? errorMessage;
  String? nicknameUpdateError;

  Future<void> restore() async {
    final restored = await repository.restoreSession();
    session = restored;
    stage = restored == null ? AuthStage.login : AuthStage.authenticated;
    notifyListeners();
  }

  Future<void> login(String nik, String pin) async {
    if (operation != null) return;
    operation = AuthOperation.login;
    errorMessage = null;
    notifyListeners();
    try {
      _apply(await repository.login(nik, pin));
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      if (error.sessionInvalid) await expireSession();
    } finally {
      operation = null;
      notifyListeners();
    }
  }

  Future<void> activate(String nickname) async {
    final pending = pendingActivation;
    if (pending == null || operation != null) return;
    operation = AuthOperation.activation;
    errorMessage = null;
    notifyListeners();
    try {
      _apply(await repository.activate(pending, nickname));
    } on AuthFailure catch (error) {
      if (error.sessionInvalid) {
        await expireSession();
        errorMessage = error.message;
      } else {
        errorMessage = error.message;
      }
    } finally {
      operation = null;
      notifyListeners();
    }
  }

  Future<bool> updateNickname(String nickname) async {
    final current = session;
    if (current == null || operation != null) return false;
    operation = AuthOperation.nicknameUpdate;
    nicknameUpdateError = null;
    notifyListeners();
    try {
      session = await repository.updateNickname(current, nickname);
      return true;
    } on AuthFailure catch (error) {
      nicknameUpdateError = error.message;
      if (error.sessionInvalid) await expireSession();
      return false;
    } finally {
      operation = null;
      notifyListeners();
    }
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await repository.logout();
    _resetToLogin();
  }

  Future<void> expireSession() async {
    await repository.logout();
    _resetToLogin();
  }

  void _apply(AuthOutcome outcome) {
    switch (outcome) {
      case Authenticated(:final session):
        this.session = session;
        pendingActivation = null;
        stage = AuthStage.authenticated;
      case ActivationRequired(:final pending):
        session = null;
        pendingActivation = pending;
        stage = AuthStage.activation;
    }
  }

  void _resetToLogin() {
    session = null;
    pendingActivation = null;
    operation = null;
    errorMessage = null;
    stage = AuthStage.login;
    notifyListeners();
  }
}
