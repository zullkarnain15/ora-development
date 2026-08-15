import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_transport.dart';
import 'apps_script_client.dart' show BackendFailure, BackendFailureKind;

ApiTransport createDefaultApiTransport() => const BrowserApiTransport();

class BrowserApiTransport implements ApiTransport {
  const BrowserApiTransport();

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async {
    final timeout = connectTimeout + readTimeout;
    try {
      final response = method == 'GET'
          ? await http
                .get(endpoint, headers: const {'Accept': 'application/json'})
                .timeout(timeout)
          : await http
                .post(
                  endpoint,
                  headers: const {
                    'Accept': 'application/json',
                    // Keep the JSON body but use a CORS-safelisted media type;
                    // Apps Script web apps do not expose an OPTIONS handler.
                    'Content-Type': 'text/plain;charset=UTF-8',
                  },
                  body: body,
                )
                .timeout(timeout);
      return TransportResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } on TimeoutException {
      throw const BackendFailure(
        BackendFailureKind.timeout,
        'ORA request timed out.',
      );
    } on Object {
      throw const BackendFailure(
        BackendFailureKind.connection,
        'Unable to reach ORA.',
      );
    }
  }
}
