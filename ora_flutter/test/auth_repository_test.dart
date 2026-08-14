import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/features/auth/application/auth_repository.dart';
import 'package:ora_flutter/features/auth/data/auth_api.dart';
import 'package:ora_flutter/features/auth/data/session_store.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';

class _FakeAuthApi implements AuthApi {
  LoginResult? loginResult;
  Participant? activationResult;
  Participant? updateResult;
  BackendFailure? loginFailure;
  BackendFailure? activationFailure;
  String? activatedNickname;
  String? updatedNickname;

  @override
  Future<LoginResult> login(String nik, String pin) async {
    if (loginFailure case final failure?) throw failure;
    return loginResult!;
  }

  @override
  Future<Participant> activateNickname(
    String sessionToken,
    String nickname,
  ) async {
    activatedNickname = nickname;
    if (activationFailure case final failure?) throw failure;
    return activationResult!;
  }

  @override
  Future<Participant> updateNickname(
    String sessionToken,
    String nickname,
  ) async {
    updatedNickname = nickname;
    return updateResult!;
  }
}

class _MalformedStore implements SessionStore {
  bool cleared = false;

  @override
  Future<UserSession?> load() => throw const FormatException('bad');

  @override
  Future<void> save(UserSession session) async {}

  @override
  Future<void> clear() async => cleared = true;
}

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);
  const returningParticipant = Participant(
    nik: '1001',
    nickname: 'RUNNER',
    divisionGuild: 'OPS',
    status: 'ACTIVE',
  );
  const newParticipant = Participant(
    nik: '1002',
    nickname: null,
    divisionGuild: 'SALES',
    status: 'ACTIVE',
  );

  AuthRepository repository(_FakeAuthApi api, SessionStore store) =>
      AuthRepository(api: api, sessionStore: store, clock: () => now);

  group('login', () {
    test('invalid credentials maps message', () async {
      final api = _FakeAuthApi()
        ..loginFailure = const BackendFailure(
          BackendFailureKind.backend,
          'invalid',
          code: 'INVALID_CREDENTIALS',
        );
      await expectLater(
        repository(api, MemorySessionStore()).login('1001', '1234'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            'NIK or PIN is incorrect.',
          ),
        ),
      );
    });

    test('inactive account is rejected', () async {
      final api = _FakeAuthApi()
        ..loginResult = const LoginResult(
          sessionToken: 'token',
          expiresInSeconds: 300,
          participant: Participant(
            nik: '1',
            nickname: 'OLD',
            divisionGuild: 'OPS',
            status: 'INACTIVE',
          ),
          requiresNicknameActivation: false,
        );
      await expectLater(
        repository(api, MemorySessionStore()).login('1', '1234'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            'This account is inactive.',
          ),
        ),
      );
    });

    test('new user requires activation and is not stored', () async {
      final store = MemorySessionStore();
      final api = _FakeAuthApi()
        ..loginResult = const LoginResult(
          sessionToken: 'pending',
          expiresInSeconds: 300,
          participant: newParticipant,
          requiresNicknameActivation: true,
        );
      final outcome = await repository(api, store).login(' 1002 ', '1234');
      expect(outcome, isA<ActivationRequired>());
      expect(store.session, isNull);
    });

    test('returning user is authenticated and stored', () async {
      final store = MemorySessionStore();
      final api = _FakeAuthApi()
        ..loginResult = const LoginResult(
          sessionToken: 'token',
          expiresInSeconds: 300,
          participant: returningParticipant,
          requiresNicknameActivation: false,
        );
      final outcome = await repository(api, store).login('1001', '1234');
      expect(outcome, isA<Authenticated>());
      expect(store.session?.nickname, 'RUNNER');
      expect(store.session?.expiresAt, now.add(const Duration(seconds: 300)));
    });
  });

  group('activation', () {
    PendingActivation pending([DateTime? expires]) => PendingActivation(
      nik: '1002',
      divisionGuild: 'SALES',
      sessionToken: 'pending',
      sessionExpiresAt: expires ?? now.add(const Duration(minutes: 5)),
    );

    test('success canonicalizes nickname and stores session', () async {
      final store = MemorySessionStore();
      final api = _FakeAuthApi()
        ..activationResult = const Participant(
          nik: '1002',
          nickname: 'HERO1',
          divisionGuild: 'SALES',
          status: 'ACTIVE',
        );
      final outcome = await repository(
        api,
        store,
      ).activate(pending(), ' hero1 ');
      expect(outcome, isA<Authenticated>());
      expect(api.activatedNickname, 'HERO1');
      expect(store.session?.nickname, 'HERO1');
    });

    test('nickname taken maps message', () async {
      final api = _FakeAuthApi()
        ..activationFailure = const BackendFailure(
          BackendFailureKind.backend,
          'taken',
          code: 'NICKNAME_TAKEN',
        );
      await expectLater(
        repository(api, MemorySessionStore()).activate(pending(), 'HERO'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            'Nickname is already in use.',
          ),
        ),
      );
    });

    test('invalid nickname is rejected before API call', () async {
      final api = _FakeAuthApi();
      await expectLater(
        repository(api, MemorySessionStore()).activate(pending(), 'BAD_NAME'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            'Use letters and numbers only.',
          ),
        ),
      );
      expect(api.activatedNickname, isNull);
    });

    test('already activated maps message', () async {
      final api = _FakeAuthApi()
        ..activationFailure = const BackendFailure(
          BackendFailureKind.backend,
          'activated',
          code: 'NICKNAME_ALREADY_ACTIVATED',
        );
      await expectLater(
        repository(api, MemorySessionStore()).activate(pending(), 'HERO'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            'Nickname has already been activated. Please login again.',
          ),
        ),
      );
    });

    test('expired pending session clears and routes as invalid', () async {
      final store = MemorySessionStore();
      final api = _FakeAuthApi();
      await expectLater(
        repository(
          api,
          store,
        ).activate(pending(now.subtract(const Duration(seconds: 1))), 'HERO'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.sessionInvalid,
            'sessionInvalid',
            isTrue,
          ),
        ),
      );
      expect(store.session, isNull);
    });
  });

  group('session lifecycle', () {
    UserSession sessionAt(DateTime expiresAt) => UserSession(
      sessionToken: 'secret',
      nik: '1001',
      nickname: 'RUNNER',
      divisionGuild: 'OPS',
      status: 'ACTIVE',
      expiresAt: expiresAt,
    );

    test('restores before expiry', () async {
      final session = sessionAt(now.add(const Duration(seconds: 1)));
      expect(
        await repository(
          _FakeAuthApi(),
          MemorySessionStore(session),
        ).restoreSession(),
        same(session),
      );
    });

    test('clears at expiry', () async {
      final store = MemorySessionStore(sessionAt(now));
      expect(await repository(_FakeAuthApi(), store).restoreSession(), isNull);
      expect(store.session, isNull);
    });

    test('clears malformed storage', () async {
      final store = _MalformedStore();
      expect(await repository(_FakeAuthApi(), store).restoreSession(), isNull);
      expect(store.cleared, isTrue);
    });

    test('logout clears session', () async {
      final store = MemorySessionStore(
        sessionAt(now.add(const Duration(days: 1))),
      );
      await repository(_FakeAuthApi(), store).logout();
      expect(store.session, isNull);
    });
  });

  test(
    'nickname update is canonicalized and persisted in the session',
    () async {
      final current = UserSession(
        sessionToken: 'secret',
        nik: '1001',
        nickname: 'RUNNER',
        divisionGuild: 'OPS',
        status: 'ACTIVE',
        expiresAt: now.add(const Duration(days: 1)),
      );
      final store = MemorySessionStore(current);
      final api = _FakeAuthApi()
        ..updateResult = const Participant(
          nik: '1001',
          nickname: 'HERO1',
          divisionGuild: 'OPS',
          status: 'ACTIVE',
        );

      final updated = await repository(
        api,
        store,
      ).updateNickname(current, ' hero1 ');

      expect(api.updatedNickname, 'HERO1');
      expect(updated.nickname, 'HERO1');
      expect(store.session?.nickname, 'HERO1');
    },
  );
}
