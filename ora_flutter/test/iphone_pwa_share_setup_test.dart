import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/app/app_shell.dart';
import 'package:ora_flutter/core/platform/iphone_pwa_share_setup_rules.dart';
import 'package:ora_flutter/core/theme/ora_theme.dart';
import 'package:ora_flutter/features/auth/application/auth_controller.dart';
import 'package:ora_flutter/features/auth/application/auth_repository.dart';
import 'package:ora_flutter/features/auth/data/auth_api.dart';
import 'package:ora_flutter/features/auth/data/session_store.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';

class _UnusedAuthApi implements AuthApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final _session = UserSession(
  sessionToken: 'fixture',
  nik: '1001',
  nickname: 'RUNNER',
  divisionGuild: 'OPS',
  status: 'ACTIVE',
  expiresAt: DateTime.utc(2030),
);

AuthController _authController() => AuthController(
  AuthRepository(api: _UnusedAuthApi(), sessionStore: MemorySessionStore()),
);

void main() {
  test('only recognizes iPhone or iPad browsers on the web', () {
    expect(
      isIphonePwaBrowser(
        isWeb: true,
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)',
      ),
      isTrue,
    );
    expect(
      isIphonePwaBrowser(
        isWeb: true,
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)',
        platform: 'MacIntel',
        maxTouchPoints: 5,
      ),
      isTrue,
    );
    expect(
      isIphonePwaBrowser(
        isWeb: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 15)',
      ),
      isFalse,
    );
    expect(
      isIphonePwaBrowser(isWeb: false, userAgent: 'Mozilla/5.0 (iPhone)'),
      isFalse,
    );
  });

  testWidgets(
    'renders and opens shortcut setup only when enabled for iPhone PWA',
    (tester) async {
      final authController = _authController();
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildOraTheme(),
          home: SettingsScreen(
            session: _session,
            authController: authController,
            onLogout: () async {},
            showIphoneShareSetup: false,
          ),
        ),
      );
      expect(find.text('IPHONE SHARE SETUP'), findsNothing);
      expect(find.byKey(const Key('install_send_to_ora')), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildOraTheme(),
          home: SettingsScreen(
            session: _session,
            authController: authController,
            onLogout: () async {},
            showIphoneShareSetup: true,
            onInstallIphoneShortcut: () async => opened = true,
          ),
        ),
      );
      expect(find.text('IPHONE SHARE SETUP'), findsOneWidget);
      expect(
        find.text('Required once to share Strava activities to ORA'),
        findsOneWidget,
      );
      final installButton = find.byKey(const Key('install_send_to_ora'));
      await tester.drag(find.byType(ListView), const Offset(0, -360));
      await tester.pumpAndSettle();
      await tester.tap(installButton);
      await tester.pump();
      expect(opened, isTrue);
      authController.dispose();
    },
  );
}
