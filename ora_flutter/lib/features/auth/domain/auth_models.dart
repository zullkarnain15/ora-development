enum AuthStage { restoring, login, activation, authenticated }

enum AuthOperation { login, activation, nicknameUpdate }

class Participant {
  const Participant({
    required this.nik,
    required this.nickname,
    required this.divisionGuild,
    required this.status,
  });

  final String nik;
  final String? nickname;
  final String divisionGuild;
  final String status;

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  factory Participant.fromJson(Map<String, Object?> json) => Participant(
    nik: _requiredString(json, 'nik'),
    nickname: _optionalString(json['nickname']),
    divisionGuild: _requiredString(json, 'divisionGuild'),
    status: _requiredString(json, 'status'),
  );
}

class LoginResult {
  const LoginResult({
    required this.sessionToken,
    required this.expiresInSeconds,
    required this.participant,
    required this.requiresNicknameActivation,
  });

  final String sessionToken;
  final int expiresInSeconds;
  final Participant participant;
  final bool requiresNicknameActivation;
}

class PendingActivation {
  const PendingActivation({
    required this.nik,
    required this.divisionGuild,
    required this.sessionToken,
    required this.sessionExpiresAt,
  });

  final String nik;
  final String divisionGuild;
  final String sessionToken;
  final DateTime sessionExpiresAt;
}

class UserSession {
  const UserSession({
    required this.sessionToken,
    required this.nik,
    required this.nickname,
    required this.divisionGuild,
    required this.status,
    required this.expiresAt,
  });

  final String sessionToken;
  final String nik;
  final String nickname;
  final String divisionGuild;
  final String status;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  UserSession copyWith({String? nickname}) => UserSession(
    sessionToken: sessionToken,
    nik: nik,
    nickname: nickname ?? this.nickname,
    divisionGuild: divisionGuild,
    status: status,
    expiresAt: expiresAt,
  );

  Map<String, Object?> toJson() => {
    'sessionToken': sessionToken,
    'nik': nik,
    'nickname': nickname,
    'divisionGuild': divisionGuild,
    'status': status,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory UserSession.fromJson(Map<String, Object?> json) => UserSession(
    sessionToken: _requiredString(json, 'sessionToken'),
    nik: _requiredString(json, 'nik'),
    nickname: _requiredString(json, 'nickname'),
    divisionGuild: _requiredString(json, 'divisionGuild'),
    status: _requiredString(json, 'status'),
    expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
  );
}

sealed class AuthOutcome {
  const AuthOutcome();
}

class Authenticated extends AuthOutcome {
  const Authenticated(this.session);
  final UserSession session;
}

class ActivationRequired extends AuthOutcome {
  const ActivationRequired(this.pending);
  final PendingActivation pending;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Required response field is missing.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid response field.');
  final trimmed = value.trim();
  return trimmed.isEmpty || trimmed == 'null' ? null : trimmed;
}
