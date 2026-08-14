import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/theme/ora_theme.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/dashboard/application/feature_controller.dart';
import '../shared/widgets/ora_widgets.dart';
import 'session_gate.dart';

class OraApp extends StatelessWidget {
  const OraApp({
    super.key,
    required this.authController,
    required this.featureControllerFactory,
    this.fatalError,
  });
  final AuthController authController;
  final FeatureControllerFactory featureControllerFactory;
  final ValueListenable<Object?>? fatalError;

  @override
  Widget build(BuildContext context) {
    Widget home = SessionGate(
      controller: authController,
      featureControllerFactory: featureControllerFactory,
    );
    final listenable = fatalError;
    if (listenable != null) {
      home = ValueListenableBuilder<Object?>(
        valueListenable: listenable,
        builder: (context, error, child) => error == null
            ? child!
            : const Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: OraStatusPanel(
                      kind: OraPanelKind.error,
                      message: 'ORA hit an unexpected error. Please restart the app.',
                    ),
                  ),
                ),
              ),
        child: home,
      );
    }
    return MaterialApp(
      title: 'ORA',
      debugShowCheckedModeBanner: false,
      theme: buildOraTheme(),
      home: home,
    );
  }
}
