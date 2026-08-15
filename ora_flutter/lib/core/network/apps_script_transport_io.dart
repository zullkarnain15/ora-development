import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_transport.dart';
import 'apps_script_client.dart' show BackendFailure, BackendFailureKind;

ApiTransport createDefaultApiTransport() => const DartIoApiTransport();

class DartIoApiTransport implements ApiTransport {
  const DartIoApiTransport();

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      var requestUri = endpoint;
      var requestMethod = method;
      var requestBody = body;
      for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
        final request = requestMethod == 'GET'
            ? await client.getUrl(requestUri).timeout(connectTimeout)
            : await client.postUrl(requestUri).timeout(connectTimeout);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          ContentType.json.mimeType,
        );
        if (requestBody != null) {
          request.headers.contentType = ContentType.json;
          request.write(requestBody);
        }
        final response = await request.close().timeout(connectTimeout);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (response.isRedirect ||
            (location != null &&
                response.statusCode >= 300 &&
                response.statusCode < 400)) {
          await response.drain<void>().timeout(readTimeout);
          if (redirectCount == 5 || location == null) {
            throw const BackendFailure(
              BackendFailureKind.connection,
              'ORA redirect could not be completed.',
            );
          }
          requestUri = requestUri.resolve(location);
          if (response.statusCode == HttpStatus.seeOther ||
              (requestMethod == 'POST' &&
                  (response.statusCode == HttpStatus.movedPermanently ||
                      response.statusCode == HttpStatus.found))) {
            requestMethod = 'GET';
            requestBody = null;
          }
          continue;
        }
        final responseBody = await utf8.decoder
            .bind(response)
            .join()
            .timeout(readTimeout);
        return TransportResponse(
          statusCode: response.statusCode,
          body: responseBody,
        );
      }
      throw const BackendFailure(
        BackendFailureKind.connection,
        'ORA redirect limit was exceeded.',
      );
    } on TimeoutException {
      throw const BackendFailure(
        BackendFailureKind.timeout,
        'ORA request timed out.',
      );
    } on SocketException {
      throw const BackendFailure(
        BackendFailureKind.connection,
        'Unable to reach ORA.',
      );
    } on HttpException {
      throw const BackendFailure(
        BackendFailureKind.connection,
        'Unable to reach ORA.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
