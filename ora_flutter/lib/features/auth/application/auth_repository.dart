import '../../../core/network/apps_script_client.dart';
import '../data/auth_api.dart';
import '../data/session_store.dart';
import '../domain/auth_models.dart';
import '../domain/auth_validation.dart';

typedef Clock = DateTime Function();

class AuthRepository {
  AuthRepository({required this.api, required this.sessionStore, Clock? clock})
    : clock = clock ?? DateTime.now;

  final AuthApi api;
  final SessionStore sessionStore;
  final Clock clock;

  Future<UserSession?> restoreSession() async {
    try {
      final session = await sessionStore.load();
      if (session == null) return null;
      if (session.isExpiredAt(clock()) ||
          session.status.toUpperCase() != 'ACTIVE') {
        await sessionStore.clear();
        return null;
      }
      return session;
    } on Object {
      await sessionStore.clear();
      return null;
    }
  }

  Future<AuthOutcome> login(String nikInput, String pin) async {
    final nikError = nikValidationError(nikInput);
    if (nikError != null) throw AuthFailure(nikError);
    final pinError = pinValidationError(pin);
    if (pinError != null) throw AuthFailure(pinError);

    try {
      final result = await api.login(nikInput.trim(), pin);
      if (!result.participant.isActive) {
        throw const AuthFailure('This account is inactive.');
      }
      final expiresAt = clock().add(Duration(seconds: result.expiresInSeconds));
      if (result.requiresNicknameActivation ||
          result.participant.nickname == null) {
        return ActivationRequired(
          PendingActivation(
            nik: result.participant.nik,
            divisionGuild: result.participant.divisionGuild,
            sessionToken: result.sessionToken,
            sessionExpiresAt: expiresAt,
          ),
        );
      }
      return await _authenticate(
        UserSession(
          sessionToken: result.sessionToken,
          nik: result.participant.nik,
          nickname: result.participant.nickname!,
          divisionGuild: result.participant.divisionGuild,
          status: result.participant.status,
          expiresAt: expiresAt,
        ),
      );
    } on BackendFailure catch (error) {
      throw AuthFailure(_userMessage(error));
    }
  }

  Future<AuthOutcome> activate(
    PendingActivation pending,
    String nicknameInput,
  ) async {
    final error = nicknameValidationError(nicknameInput);
    if (error != null) throw AuthFailure(error);
    if (!pending.sessionExpiresAt.isAfter(clock())) {
      await sessionStore.clear();
      throw const AuthFailure(
        'Session expired. Please login again.',
        sessionInvalid: true,
      );
    }
    final nickname = canonicalNickname(nicknameInput);
    try {
      final participant = await api.activateNickname(
        pending.sessionToken,
        nickname,
      );
      if (!participant.isActive) {
        throw const AuthFailure('This account is inactive.');
      }
      return await _authenticate(
        UserSession(
          sessionToken: pending.sessionToken,
          nik: participant.nik,
          nickname: participant.nickname ?? nickname,
          divisionGuild: participant.divisionGuild,
          status: participant.status,
          expiresAt: pending.sessionExpiresAt,
        ),
      );
    } on BackendFailure catch (error) {
      throw AuthFailure(
        _userMessage(error),
        sessionInvalid: error.invalidatesSession,
      );
    }
  }

  Future<UserSession> updateNickname(
    UserSession current,
    String nicknameInput,
  ) async {
    final error = nicknameValidationError(nicknameInput);
    if (error != null) throw AuthFailure(error);
    if (current.isExpiredAt(clock())) {
      await sessionStore.clear();
      throw const AuthFailure(
        'Session expired. Please login again.',
        sessionInvalid: true,
      );
    }
    final nickname = canonicalNickname(nicknameInput);
    try {
      final participant = await api.updateNickname(
        current.sessionToken,
        nickname,
      );
      if (participant.nik != current.nik || !participant.isActive) {
        throw const AuthFailure('Unable to update nickname.');
      }
      final updated = current.copyWith(
        nickname: participant.nickname ?? nickname,
      );
      await sessionStore.save(updated);
      return updated;
    } on BackendFailure catch (error) {
      throw AuthFailure(
        _userMessage(error),
        sessionInvalid: error.invalidatesSession,
      );
    }
  }

  Future<Authenticated> _authenticate(UserSession session) async {
    await sessionStore.save(session);
    return Authenticated(session);
  }

  Future<void> logout() => sessionStore.clear();

  String _userMessage(BackendFailure error) => switch (error.code) {
    'INVALID_CREDENTIALS' => 'NIK or PIN is incorrect.',
    'ACCOUNT_INACTIVE' => 'This account is inactive.',
    'NICKNAME_TAKEN' => 'Nickname is already in use.',
    'INVALID_NICKNAME' =>
      error.message.isEmpty ? 'Nickname is invalid.' : error.message,
    'NICKNAME_ALREADY_ACTIVATED' =>
      'Nickname has already been activated. Please login again.',
    'SESSION_EXPIRED' ||
    'UNAUTHORIZED' => 'Session expired. Please login again.',
    _ => 'Unable to connect to ORA. Check your connection and try again.',
  };
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.sessionInvalid = false});
  final String message;
  final bool sessionInvalid;
}
