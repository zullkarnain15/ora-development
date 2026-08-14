import '../../../core/network/apps_script_client.dart';
import '../domain/auth_models.dart';

abstract interface class AuthApi {
  Future<LoginResult> login(String nik, String pin);
  Future<Participant> activateNickname(String sessionToken, String nickname);
  Future<Participant> updateNickname(String sessionToken, String nickname);
}

class AppsScriptAuthApi implements AuthApi {
  const AppsScriptAuthApi(this.client);
  final AppsScriptClient client;

  @override
  Future<LoginResult> login(String nik, String pin) async {
    final data = await client.call('login', {'nik': nik, 'pin': pin});
    try {
      final participantJson = data['participant'];
      if (participantJson is! Map<String, Object?>) {
        throw const FormatException('Participant is missing.');
      }
      final token = data['sessionToken'];
      final expires = data['expiresInSeconds'];
      if (token is! String ||
          token.isEmpty ||
          expires is! num ||
          expires.toInt() <= 0) {
        throw const FormatException('Session fields are invalid.');
      }
      return LoginResult(
        sessionToken: token,
        expiresInSeconds: expires.toInt(),
        participant: Participant.fromJson(participantJson),
        requiresNicknameActivation: data['requiresNicknameActivation'] == true,
      );
    } on FormatException {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Login response fields are invalid.',
      );
    }
  }

  @override
  Future<Participant> activateNickname(
    String sessionToken,
    String nickname,
  ) async {
    final data = await client.call('activateNickname', {
      'sessionToken': sessionToken,
      'nickname': nickname,
    });
    try {
      final participantJson = data['participant'];
      if (participantJson is! Map<String, Object?>) {
        throw const FormatException('Participant is missing.');
      }
      return Participant.fromJson(participantJson);
    } on FormatException {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Activation response fields are invalid.',
      );
    }
  }

  @override
  Future<Participant> updateNickname(
    String sessionToken,
    String nickname,
  ) async {
    final data = await client.call('updateNickname', {
      'sessionToken': sessionToken,
      'nickname': nickname,
    });
    try {
      final participantJson = data['participant'];
      if (participantJson is! Map<String, Object?>) {
        throw const FormatException('Participant is missing.');
      }
      return Participant.fromJson(participantJson);
    } on FormatException {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Nickname update response fields are invalid.',
      );
    }
  }
}
