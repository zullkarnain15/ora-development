import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/apps_script_client.dart';
import '../domain/activity_share_payload.dart';

abstract interface class ActivityImportBridgeApi {
  Future<String> createTemporaryPayload(ActivitySharePayload payload);
  Future<ActivitySharePayload> fetchTemporaryPayload(String token);
  Future<void> consumeTemporaryPayload(String token);
}

class AppsScriptActivityImportBridgeApi implements ActivityImportBridgeApi {
  const AppsScriptActivityImportBridgeApi(this.client);

  final AppsScriptClient client;

  @override
  Future<String> createTemporaryPayload(ActivitySharePayload payload) async {
    final image = payload.images.isEmpty ? null : payload.images.first;
    final data = await client.call('createImportToken', {
      'sharedText': payload.sharedText,
      'sharedUrl': payload.sharedUrl,
      'sourceHint': payload.sourceHint,
      if (image != null) ...{
        'imageBase64': base64Encode(image.bytes),
        'imageMimeType': image.mimeType,
        'imageName': image.name,
      },
    });
    final token = data['importToken'];
    if (token is! String || token.trim().isEmpty) {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Import token is missing.',
      );
    }
    return token.trim();
  }

  @override
  Future<ActivitySharePayload> fetchTemporaryPayload(String token) async {
    final data = await client.call('getImportPayload', {'importToken': token});
    final payload = data['payload'];
    if (payload is! Map<String, Object?>) {
      throw const BackendFailure(
        BackendFailureKind.invalidResponse,
        'Import payload is missing.',
      );
    }
    final imageText = payload['imageBase64'];
    final images = <ActivityShareImage>[];
    if (imageText is String && imageText.isNotEmpty) {
      Uint8List bytes;
      try {
        bytes = base64Decode(imageText);
      } on FormatException {
        throw const BackendFailure(
          BackendFailureKind.invalidResponse,
          'Import image is invalid.',
        );
      }
      images.add(
        ActivityShareImage(
          bytes: bytes,
          mimeType: _string(payload['imageMimeType']) ?? 'image/jpeg',
          name: _string(payload['imageName']),
        ),
      );
    }
    final receivedAt = DateTime.tryParse(_string(payload['receivedAt']) ?? '');
    return ActivitySharePayload(
      sharedText: _string(payload['sharedText']),
      sharedUrl: _string(payload['sharedUrl']),
      sourceHint: _string(payload['sourceHint']),
      images: images,
      receivedAt: receivedAt?.toLocal() ?? DateTime.now(),
    );
  }

  @override
  Future<void> consumeTemporaryPayload(String token) async {
    await client.call('consumeImportToken', {'importToken': token});
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
