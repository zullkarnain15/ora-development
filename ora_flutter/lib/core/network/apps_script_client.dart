import 'dart:async';
import 'dart:convert';

import 'api_transport.dart';
import 'apps_script_transport_io.dart'
    if (dart.library.js_interop) 'apps_script_transport_web.dart';

export 'api_transport.dart';
export 'apps_script_transport_io.dart'
    if (dart.library.js_interop) 'apps_script_transport_web.dart';

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

typedef SessionInvalidCallback = FutureOr<void> Function();

class AppsScriptClient {
  AppsScriptClient({
    Uri? endpoint,
    ApiTransport? transport,
    this.connectTimeout = const Duration(seconds: 15),
    this.readTimeout = const Duration(seconds: 20),
    this.onSessionInvalid,
  }) : endpoint = endpoint ?? Uri.parse(oraBackendUrl),
       transport = transport ?? createDefaultApiTransport();

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
