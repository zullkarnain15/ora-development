import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/features/activity_import/data/activity_import_bridge_api.dart';
import 'package:ora_flutter/features/activity_import/domain/activity_share_payload.dart';

class _BridgeTransport implements ApiTransport {
  final requests = <Map<String, Object?>>[];

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async {
    final request = jsonDecode(body!) as Map<String, Object?>;
    requests.add(request);
    return switch (request['action']) {
      'createImportToken' => const TransportResponse(
        statusCode: 200,
        body: '{"ok":true,"data":{"importToken":"token-123"}}',
      ),
      'getImportPayload' => TransportResponse(
        statusCode: 200,
        body: jsonEncode({
          'ok': true,
          'data': {
            'payload': {
              'sharedText': 'Morning Run 5 km 30:00',
              'sharedUrl': 'https://strava.com/activities/1',
              'sourceHint': 'STRAVA',
              'receivedAt': '2026-08-25T01:00:00.000Z',
              'imageBase64': base64Encode([1, 2, 3]),
              'imageMimeType': 'image/png',
              'imageName': 'share.png',
            },
          },
        }),
      ),
      'consumeImportToken' => const TransportResponse(
        statusCode: 200,
        body: '{"ok":true,"data":{"status":"CONSUMED"}}',
      ),
      _ => throw StateError('Unexpected action'),
    };
  }
}

void main() {
  test('creates, fetches, and consumes an opaque temporary token', () async {
    final transport = _BridgeTransport();
    final api = AppsScriptActivityImportBridgeApi(
      AppsScriptClient(transport: transport),
    );
    final token = await api.createTemporaryPayload(
      ActivitySharePayload(
        sharedText: 'Morning Run',
        sourceHint: 'STRAVA',
        images: [
          ActivityShareImage(
            bytes: Uint8List.fromList([4, 5, 6]),
            mimeType: 'image/png',
            name: 'activity.png',
          ),
        ],
        receivedAt: DateTime(2026, 8, 25),
      ),
    );
    final payload = await api.fetchTemporaryPayload(token);
    await api.consumeTemporaryPayload(token);

    expect(token, 'token-123');
    expect(payload.sourceHint, 'STRAVA');
    expect(payload.images.single.bytes, Uint8List.fromList([1, 2, 3]));
    expect(transport.requests.map((request) => request['action']), [
      'createImportToken',
      'getImportPayload',
      'consumeImportToken',
    ]);
    expect(transport.requests.first, isNot(contains('sessionToken')));
    expect(transport.requests.first['imageBase64'], base64Encode([4, 5, 6]));
  });

  test('preserves backend lifecycle error codes', () async {
    final client = AppsScriptClient(
      transport: _ErrorTransport('IMPORT_ALREADY_USED'),
    );
    final api = AppsScriptActivityImportBridgeApi(client);

    await expectLater(
      api.fetchTemporaryPayload('used-token'),
      throwsA(
        isA<BackendFailure>().having(
          (error) => error.code,
          'code',
          'IMPORT_ALREADY_USED',
        ),
      ),
    );
  });
}

class _ErrorTransport implements ApiTransport {
  const _ErrorTransport(this.code);
  final String code;

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async => TransportResponse(
    statusCode: 200,
    body: jsonEncode({
      'ok': false,
      'error': {'code': code, 'message': 'fixture'},
    }),
  );
}
