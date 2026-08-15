import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_transport_web.dart';

void main() {
  test(
    'Web transport sends JSON using a CORS-safelisted content type',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      late String contentType;
      late Map<String, Object?> payload;
      server.listen((request) async {
        contentType = request.headers.contentType.toString();
        payload = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, Object?>;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true}');
        await request.response.close();
      });

      final response = await const BrowserApiTransport().request(
        Uri.parse('http://${server.address.address}:${server.port}/exec'),
        method: 'POST',
        body: '{"action":"login","nik":"1001","pin":"1234"}',
        connectTimeout: const Duration(seconds: 2),
        readTimeout: const Duration(seconds: 2),
      );

      expect(response.statusCode, 200);
      expect(contentType, startsWith('text/plain'));
      expect(payload['action'], 'login');
    },
  );
}
