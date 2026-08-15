import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/network/apps_script_client.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_repository.dart';
import '../features/auth/data/auth_api.dart';
import '../features/activity/data/activity_store.dart';
import '../features/activity/data/activity_store_factory.dart';
import '../features/auth/data/session_store_factory.dart';
import '../features/dashboard/application/feature_controller.dart';
import '../features/dashboard/data/ora_feature_api.dart';
import 'ora_app.dart';

void bootstrapOra() {
  final fatalError = ValueNotifier<Object?>(null);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    fatalError.value = details.exception;
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    fatalError.value = error;
    return true;
  };

  late final AuthController authController;
  final client = AppsScriptClient(
    onSessionInvalid: () => authController.expireSession(),
  );
  authController = AuthController(
    AuthRepository(
      api: AppsScriptAuthApi(client),
      sessionStore: createSessionStore(),
    ),
  );
  final featureApi = AppsScriptFeatureApi(client);
  final ActivityStore activityStore = createActivityStore();
  runApp(
    OraApp(
      authController: authController,
      featureControllerFactory: (session) => FeatureController(
        session: session,
        api: featureApi,
        activityStore: activityStore,
      ),
      fatalError: fatalError,
    ),
  );
  unawaited(authController.restore());
}
