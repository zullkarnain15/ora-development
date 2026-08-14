import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/features/auth/application/auth_controller.dart';
import 'package:ora_flutter/features/auth/application/auth_repository.dart';
import 'package:ora_flutter/features/auth/data/auth_api.dart';
import 'package:ora_flutter/features/auth/data/session_store.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';

class _NoopApi implements AuthApi {
  @override
  Future<Participant> activateNickname(String sessionToken, String nickname) =>
      throw UnimplementedError();

  @override
  Future<LoginResult> login(String nik, String pin) =>
      throw UnimplementedError();

  @override
  Future<Participant> updateNickname(String sessionToken, String nickname) =>
      throw UnimplementedError();
}

class _ExpiredTransport implements ApiTransport {
  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async => const TransportResponse(
    statusCode: 200,
    body: '{"ok":false,"error":{"code":"UNAUTHORIZED","message":"No session"}}',
  );
}

void main() {
  test(
    'centralized unauthorized response clears session and routes to login',
    () async {
      final storedSession = UserSession(
        sessionToken: 'fixture-token',
        nik: '1001',
        nickname: 'RUNNER',
        divisionGuild: 'OPS',
        status: 'ACTIVE',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      final store = MemorySessionStore(storedSession);
      final controller = AuthController(
        AuthRepository(api: _NoopApi(), sessionStore: store),
      );
      await controller.restore();
      expect(controller.stage, AuthStage.authenticated);

      final client = AppsScriptClient(
        transport: _ExpiredTransport(),
        onSessionInvalid: controller.expireSession,
      );
      await expectLater(
        client.call('getUserStats'),
        throwsA(isA<BackendFailure>()),
      );
      expect(controller.stage, AuthStage.login);
      expect(controller.session, isNull);
      expect(store.session, isNull);
    },
  );
}
