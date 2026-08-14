import 'package:flutter/material.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/auth/presentation/activation_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/dashboard/application/feature_controller.dart';
import '../shared/widgets/ora_widgets.dart';
import 'app_shell.dart';

class SessionGate extends StatelessWidget {
  const SessionGate({
    super.key,
    required this.controller,
    required this.featureControllerFactory,
  });
  final AuthController controller;
  final FeatureControllerFactory featureControllerFactory;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => switch (controller.stage) {
      AuthStage.restoring => const Scaffold(
        body: Center(
          child: OraStatusPanel(
            kind: OraPanelKind.loading,
            message: 'RESTORING ADVENTURER...',
          ),
        ),
      ),
      AuthStage.login => LoginScreen(
        errorMessage: controller.errorMessage,
        isLoading: controller.operation == AuthOperation.login,
        onClearError: controller.clearError,
        onLogin: controller.login,
      ),
      AuthStage.activation => ActivationScreen(
        divisionGuild: controller.pendingActivation!.divisionGuild,
        errorMessage: controller.errorMessage,
        isLoading: controller.operation == AuthOperation.activation,
        onClearError: controller.clearError,
        onActivate: controller.activate,
      ),
      AuthStage.authenticated => AppShell(
        session: controller.session!,
        authController: controller,
        featureControllerFactory: featureControllerFactory,
      ),
    },
  );
}
