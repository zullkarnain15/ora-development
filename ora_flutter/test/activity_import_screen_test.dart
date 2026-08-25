import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity_import/application/activity_import_controller.dart';
import 'package:ora_flutter/features/activity_import/application/activity_import_inbox.dart';
import 'package:ora_flutter/features/activity_import/data/activity_import_bridge_api.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_share_payload.dart';
import 'package:ora_flutter/features/activity_import/presentation/activity_import_screen.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/dashboard/application/feature_controller.dart';
import 'package:ora_flutter/features/dashboard/data/ora_feature_api.dart';

class _UnusedFeatureApi implements OraFeatureApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _UnusedBridgeApi implements ActivityImportBridgeApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  final session = UserSession(
    sessionToken: 'fixture',
    nik: '1001',
    nickname: 'RUNNER',
    divisionGuild: 'OPS',
    status: 'ACTIVE',
    expiresAt: DateTime.utc(2030),
  );

  ActivityImportController createController(String text) {
    final inbox = ActivityImportInbox();
    final featureController = FeatureController(
      session: session,
      api: _UnusedFeatureApi(),
      activityStore: MemoryActivityStore(),
    );
    return ActivityImportController(
      launch: ActivityImportLaunch(
        payload: ActivitySharePayload(
          sharedText: text,
          sharedUrl: 'https://www.strava.com/activities/123',
          receivedAt: DateTime(2026, 8, 25),
        ),
      ),
      inbox: inbox,
      bridgeApi: _UnusedBridgeApi(),
      featureController: featureController,
    );
  }

  testWidgets('preview shows parsed fields and enables confirmed save', (
    tester,
  ) async {
    final controller = createController(
      'Morning Run\n8.09 km\n58:06\n7:10/km\n25 Aug 2026\nStarted at 06:10',
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityImportScreen(controller: controller, onClose: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('SHARED ACTIVITY'), findsNWidgets(2));
    expect(find.text('STRAVA'), findsOneWidget);
    expect(find.text('8.09 KM'), findsOneWidget);
    expect(find.text('58:06'), findsOneWidget);
    expect(find.text('07:11 /KM'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('import_reparse')), findsNothing);
    expect(find.byKey(const Key('import_screenshot')), findsNothing);
    controller.updateDate(DateTime(2026, 8, 25));
    controller.updateTime(6, 10);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import_save')))
          .onPressed,
      isNotNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.featureController.dispose();
    controller.inbox.dispose();
    controller.dispose();
  });

  test('date and time must both be explicitly selected', () async {
    final controller = createController('Strava\n5 km\n30:00');
    await controller.initialize();
    controller.updateDate(DateTime(2026, 8, 25));

    expect(controller.selectedDate, DateTime(2026, 8, 25));
    expect(controller.draft?.startDateTime, isNull);
    expect(controller.draft?.canSave, isFalse);

    controller.updateTime(6, 10);
    expect(controller.draft?.startDateTime, DateTime(2026, 8, 25, 6, 10));
    expect(controller.draft?.canSave, isTrue);

    controller.featureController.dispose();
    controller.inbox.dispose();
    controller.dispose();
  });
}
