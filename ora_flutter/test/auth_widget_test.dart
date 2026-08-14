import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/app/app_shell.dart';
import 'package:ora_flutter/app/ora_app.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/core/theme/ora_theme.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/auth/application/auth_controller.dart';
import 'package:ora_flutter/features/auth/application/auth_repository.dart';
import 'package:ora_flutter/features/auth/data/auth_api.dart';
import 'package:ora_flutter/features/auth/data/session_store.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/auth/presentation/activation_screen.dart';
import 'package:ora_flutter/features/auth/presentation/login_screen.dart';
import 'package:ora_flutter/features/dashboard/application/feature_controller.dart';
import 'package:ora_flutter/features/dashboard/data/ora_feature_api.dart';

class _UnusedApi implements AuthApi {
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

class _OfflineTransport implements ApiTransport {
  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async => const TransportResponse(
    statusCode: 200,
    body: '{"ok":false,"error":{"code":"OFFLINE","message":"fixture"}}',
  );
}

FeatureController _featureFactory(UserSession session) => FeatureController(
  session: session,
  api: AppsScriptFeatureApi(AppsScriptClient(transport: _OfflineTransport())),
  activityStore: MemoryActivityStore(),
);

Widget _host(Widget child) => MaterialApp(theme: buildOraTheme(), home: child);

void main() {
  testWidgets('login shows error and loading states', (tester) async {
    await tester.pumpWidget(
      _host(
        LoginScreen(
          errorMessage: 'NIK or PIN is incorrect.',
          isLoading: false,
          onClearError: () {},
          onLogin: (_, _) async {},
        ),
      ),
    );
    expect(find.text('NIK or PIN is incorrect.'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        LoginScreen(
          errorMessage: null,
          isLoading: true,
          onClearError: () {},
          onLogin: (_, _) async {},
        ),
      ),
    );
    expect(find.text('CONNECTING...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login_submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('login keyboard done submits NIK and PIN', (tester) async {
    String? submittedNik;
    String? submittedPin;
    await tester.pumpWidget(
      _host(
        LoginScreen(
          errorMessage: null,
          isLoading: false,
          onClearError: () {},
          onLogin: (nik, pin) async {
            submittedNik = nik;
            submittedPin = pin;
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('login_nik')), '1001');
    await tester.enterText(find.byKey(const Key('login_pin')), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submittedNik, '1001');
    expect(submittedPin, '1234');
  });

  testWidgets('activation supports loading, error, and keyboard submit', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      _host(
        ActivationScreen(
          divisionGuild: 'OPS',
          errorMessage: 'Nickname is already in use.',
          isLoading: false,
          onClearError: () {},
          onActivate: (nickname) async => submitted = nickname,
        ),
      ),
    );
    expect(find.text('Nickname is already in use.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('activation_nickname')),
      'hero',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, 'hero');

    await tester.pumpWidget(
      _host(
        ActivationScreen(
          divisionGuild: 'OPS',
          errorMessage: null,
          isLoading: true,
          onClearError: () {},
          onActivate: (_) async {},
        ),
      ),
    );
    expect(find.text('ACTIVATING...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('activation_submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'shell navigates five destinations and settings hides navigation',
    (tester) async {
      final controller = AuthController(
        AuthRepository(api: _UnusedApi(), sessionStore: MemorySessionStore()),
      );
      final session = UserSession(
        sessionToken: 'secret',
        nik: '1001',
        nickname: 'RUNNER',
        divisionGuild: 'OPS',
        status: 'ACTIVE',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      await tester.pumpWidget(
        _host(
          AppShell(
            session: session,
            authController: controller,
            featureControllerFactory: _featureFactory,
          ),
        ),
      );
      expect(find.text('WELCOME,'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_quest')));
      await tester.pump();
      expect(find.text('QUEST BOARD'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_run')));
      await tester.pump();
      expect(find.text('OFFLINE GPS TRACKING'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_guild')));
      await tester.pump();
      expect(find.text('GUILD HALL'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_you')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('open_settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byKey(const Key('edit_nickname')));
      await tester.pumpAndSettle();
      expect(find.text('EDIT NICKNAME'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('nickname_edit_input')))
            .controller
            ?.text,
        'RUNNER',
      );
    },
  );

  testWidgets('logout from settings clears the authenticated route stack', (
    tester,
  ) async {
    final session = UserSession(
      sessionToken: 'secret',
      nik: '1001',
      nickname: 'RUNNER',
      divisionGuild: 'OPS',
      status: 'ACTIVE',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final store = MemorySessionStore(session);
    final controller = AuthController(
      AuthRepository(api: _UnusedApi(), sessionStore: store),
    );
    await controller.restore();
    await tester.pumpWidget(
      OraApp(
        authController: controller,
        featureControllerFactory: _featureFactory,
      ),
    );
    await tester.tap(find.byKey(const Key('nav_you')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('open_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(find.text('ENTER ORA'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(store.session, isNull);
  });

  testWidgets('system back returns to Home before requiring double back exit', (
    tester,
  ) async {
    final controller = AuthController(
      AuthRepository(api: _UnusedApi(), sessionStore: MemorySessionStore()),
    );
    final session = UserSession(
      sessionToken: 'secret',
      nik: '1001',
      nickname: 'RUNNER',
      divisionGuild: 'OPS',
      status: 'ACTIVE',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    await tester.pumpWidget(
      _host(
        AppShell(
          session: session,
          authController: controller,
          featureControllerFactory: _featureFactory,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('nav_quest')));
    await tester.pump();
    expect(find.text('QUEST BOARD'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('WELCOME,'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('PRESS BACK AGAIN TO EXIT'), findsOneWidget);
  });
}
