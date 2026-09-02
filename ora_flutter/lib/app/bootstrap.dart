import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/network/apps_script_client.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_repository.dart';
import '../features/auth/data/auth_api.dart';
import '../features/activity/data/activity_store.dart';
import '../features/activity/data/activity_store_factory.dart';
import '../features/activity_import/application/activity_import_inbox.dart';
import '../features/activity_import/data/activity_import_bridge_api.dart';
import '../features/auth/data/session_store_factory.dart';
import '../features/dashboard/application/feature_controller.dart';
import '../features/dashboard/data/feature_cache_store_factory.dart';
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
  final importInbox = ActivityImportInbox();
  final importBridgeApi = AppsScriptActivityImportBridgeApi(client);
  final ActivityStore activityStore = createActivityStore();
  final featureCacheStore = createFeatureCacheStore();
  runApp(
    OraApp(
      authController: authController,
      featureControllerFactory: (session) => FeatureController(
        session: session,
        api: featureApi,
        activityStore: activityStore,
        cacheStore: featureCacheStore,
      ),
      importInbox: importInbox,
      importBridgeApi: importBridgeApi,
      fatalError: fatalError,
    ),
  );
  unawaited(importInbox.initialize());
  unawaited(authController.restore());
}
