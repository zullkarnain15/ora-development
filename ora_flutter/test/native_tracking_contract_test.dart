import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/tracking/data/native_tracking_adapter.dart';
import 'package:ora_flutter/features/tracking/domain/tracking_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ora/tracking/methods/v1');
  final calls = <MethodCall>[];

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  test(
    'versioned native contract serializes clock, status, and commands',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'clockSnapshot') {
              return <String, Object>{
                'monotonicMillis': 50,
                'epochMillis': 1050,
                'bootEpochMillis': 1000,
              };
            }
            if (call.method == 'status') {
              return <String, Object>{
                'permission': 'approximate',
                'locationEnabled': true,
                'serviceActive': false,
                'notificationGranted': false,
              };
            }
            return null;
          });
      const adapter = MethodChannelTrackingAdapter();
      expect((await adapter.snapshot()).monotonicMillis, 50);
      expect(
        (await adapter.status()).permission,
        LocationPermissionState.approximate,
      );
      await adapter.start('S1');
      final arguments = calls.last.arguments as Map<Object?, Object?>;
      expect(calls.last.method, 'start');
      expect(arguments['contractVersion'], 1);
      expect(arguments['sessionId'], 'S1');
    },
  );

  test(
    'native platform errors are normalized without leaking details',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'PRECISE_LOCATION_REQUIRED',
              message: 'Precise location is required.',
              details: 'native-private-detail',
            );
          });
      const adapter = MethodChannelTrackingAdapter();
      await expectLater(
        adapter.start('S1'),
        throwsA(
          isA<NativeTrackingFailure>()
              .having(
                (error) => error.code,
                'code',
                'PRECISE_LOCATION_REQUIRED',
              )
              .having(
                (error) => error.toString().contains('native-private-detail'),
                'does not expose details',
                isFalse,
              ),
        ),
      );
    },
  );
}
