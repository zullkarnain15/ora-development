import 'dart:async';
import 'dart:convert';
import 'dart:io';

const oraBackendUrl = String.fromEnvironment(
  'ORA_BACKEND_URL',
  defaultValue: 'https://script.google.com/macros/s/AKfycbyD2oOTr39col6dqHTd721TFNizut4-Gi9jSe5CLYaTwMqx1mlQT1jD-JK8fqHSVWsn/exec',
);

enum BackendFailureKind {
  backend,
  invalidResponse,
  emptyResponse,
  timeout,
  connection,
}

class BackendFailure implements Exception {
  const BackendFailure(this.kind, this.message, {this.code});
  final BackendFailureKind kind;
  final String message;
  final String? code;

  bool get invalidatesSession =>
      code == 'UNAUTHORIZED' || code == 'SESSION_EXPIRED';

  @override
  String toString() => 'BackendFailure($kind, $code)';
}

class TransportResponse {
  const TransportResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

abstract interface class ApiTransport {
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  });
}

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

typedef SessionInvalidCallback = FutureOr<void> Function();

class AppsScriptClient {
  AppsScriptClient({
    Uri? endpoint,
    ApiTransport? transport,
    this.connectTimeout = const Duration(seconds: 15),
    this.readTimeout = const Duration(seconds: 20),
    this.onSessionInvalid,
  }) : endpoint = endpoint ?? Uri.parse(oraBackendUrl),
       transport = transport ?? const DartIoApiTransport();

  final Uri endpoint;
  final ApiTransport transport;
  final Duration connectTimeout;
  final Duration readTimeout;
  final SessionInvalidCallback? onSessionInvalid;

  Future<Map<String, Object?>> get(String action) {
    final uri = endpoint.replace(
      queryParameters: {...endpoint.queryParameters, 'action': action},
    );
    return _request(uri, method: 'GET');
  }

  Future<Map<String, Object?>> call(
    String action, [
    Map<String, Object?> payload = const {},
  ]) => _request(
    endpoint,
    method: 'POST',
    body: jsonEncode({'action': action, ...payload}),
  );

  Future<Map<String, Object?>> _request(
    Uri requestUri, {
    required String method,
    String? body,
  }) async {
    TransportResponse response;
    try {
      response = await transport.request(
        requestUri,
        method: method,
        body: body,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
      );
    } on BackendFailure {
      rethrow;
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

    if (response.body.trim().isEmpty) {
      throw const BackendFailure(
        BackendFailureKind.emptyResponse,
        'Backend returned an empty response.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Backend response is not valid JSON.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Backend response must be an object.',
      );
    }
    if (decoded['ok'] != true) {
      final error = decoded['error'];
      final errorMap = error is Map<String, Object?>
          ? error
          : const <String, Object?>{};
      final code = errorMap['code'] is String
          ? errorMap['code']! as String
          : 'BACKEND_ERROR';
      final message = errorMap['message'] is String
          ? errorMap['message']! as String
          : 'Backend ORA rejected the request.';
      final failure = BackendFailure(
        BackendFailureKind.backend,
        message,
        code: code,
      );
      if (failure.invalidatesSession) await onSessionInvalid?.call();
      throw failure;
    }
    final data = decoded['data'];
    if (data == null) return decoded;
    if (data is Map<String, Object?>) return data;
    throw const BackendFailure(
      BackendFailureKind.invalidResponse,
      'Backend data must be an object.',
    );
  }
}
