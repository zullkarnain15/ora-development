import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';

class _Transport implements ApiTransport {
  _Transport(this.handler);
  final Future<TransportResponse> Function(String body) handler;

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) => handler(body ?? '');
}

void main() {
  test('nested success returns data and preserves action payload', () async {
    late Map<String, Object?> request;
    final client = AppsScriptClient(
      transport: _Transport((body) async {
        request = jsonDecode(body) as Map<String, Object?>;
        return const TransportResponse(
          statusCode: 200,
          body: '{"ok":true,"data":{"value":7}}',
        );
      }),
    );
    expect(await client.call('login', {'nik': '10'}), {'value': 7});
    expect(request, {'action': 'login', 'nik': '10'});
  });

  test('flat success returns successful root', () async {
    final client = AppsScriptClient(
      transport: _Transport(
        (_) async => const TransportResponse(
          statusCode: 200,
          body: '{"ok":true,"stats":{"xp":4}}',
        ),
      ),
    );
    expect((await client.call('getUserStats'))['stats'], {'xp': 4});
  });

  test('backend error preserves code', () async {
    final client = AppsScriptClient(
      transport: _Transport(
        (_) async => const TransportResponse(
          statusCode: 200,
          body: '{"ok":false,"error":{"code":"INVALID_CREDENTIALS","message":"No"}}',
        ),
      ),
    );
    await expectLater(
      client.call('login'),
      throwsA(
        isA<BackendFailure>().having(
          (error) => error.code,
          'code',
          'INVALID_CREDENTIALS',
        ),
      ),
    );
  });

  test('invalid JSON and empty response are normalized', () async {
    final invalid = AppsScriptClient(
      transport: _Transport(
        (_) async => const TransportResponse(statusCode: 200, body: '<html>'),
      ),
    );
    final empty = AppsScriptClient(
      transport: _Transport(
        (_) async => const TransportResponse(statusCode: 200, body: '  '),
      ),
    );
    await expectLater(
      invalid.call('login'),
      throwsA(
        isA<BackendFailure>().having(
          (error) => error.kind,
          'kind',
          BackendFailureKind.invalidResponse,
        ),
      ),
    );
    await expectLater(
      empty.call('login'),
      throwsA(
        isA<BackendFailure>().having(
          (error) => error.kind,
          'kind',
          BackendFailureKind.emptyResponse,
        ),
      ),
    );
  });

  test('timeout is normalized', () async {
    final client = AppsScriptClient(
      transport: _Transport((_) async => throw TimeoutException('late')),
    );
    await expectLater(
      client.call('login'),
      throwsA(
        isA<BackendFailure>().having(
          (error) => error.kind,
          'kind',
          BackendFailureKind.timeout,
        ),
      ),
    );
  });

  test('session expiry invokes centralized callback', () async {
    var expired = false;
    final client = AppsScriptClient(
      onSessionInvalid: () => expired = true,
      transport: _Transport(
        (_) async => const TransportResponse(
          statusCode: 200,
          body: '{"ok":false,"error":{"code":"SESSION_EXPIRED","message":"Expired"}}',
        ),
      ),
    );
    await expectLater(
      client.call('getUserStats'),
      throwsA(isA<BackendFailure>()),
    );
    expect(expired, isTrue);
  });

  test('dart IO transport follows Apps Script style POST 302 as GET', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var redirectedMethod = '';
    server.listen((request) async {
      if (request.uri.path == '/exec') {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/result');
        await request.response.close();
      } else {
        redirectedMethod = request.method;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true,"data":{"value":9}}');
        await request.response.close();
      }
    });
    final client = AppsScriptClient(
      endpoint: Uri.parse(
        'http://${server.address.address}:${server.port}/exec',
      ),
      transport: const DartIoApiTransport(),
    );
    expect((await client.call('config'))['value'], 9);
    expect(redirectedMethod, 'GET');
  });
}
