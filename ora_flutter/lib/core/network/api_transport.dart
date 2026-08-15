abstract interface class ApiTransport {
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  });
}

class TransportResponse {
  const TransportResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
