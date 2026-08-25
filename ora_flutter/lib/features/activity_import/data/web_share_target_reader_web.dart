import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/activity_share_payload.dart';

const _maxImageBytes = 5 * 1024 * 1024;
final _validShareId = RegExp(r'^[a-zA-Z0-9-]+$');

Future<ActivitySharePayload?> readPlatformWebShareTargetPayload(Uri uri) async {
  if (uri.queryParameters['share_target'] != '1') return null;
  final shareId = uri.queryParameters['share_id']?.trim();
  if (shareId == null || !_validShareId.hasMatch(shareId)) return null;

  final metadataUri = uri.resolve('_ora_share_payload/$shareId.json');
  final imageUri = uri.resolve('_ora_share_payload/$shareId.image');
  final deleteUri = uri.resolve('_ora_share_payload/$shareId');
  try {
    final metadataResponse = await http.get(metadataUri);
    if (metadataResponse.statusCode != 200) return null;
    final decoded = jsonDecode(metadataResponse.body);
    if (decoded is! Map<String, Object?>) return null;

    final title = _string(decoded['title']);
    final text = _string(decoded['text']);
    final sharedUrl = _string(decoded['url']);
    final combinedText = [?title, ?text].join('\n');
    final images = <ActivityShareImage>[];
    if (decoded['hasImage'] == true) {
      final imageResponse = await http.get(imageUri);
      if (imageResponse.statusCode == 200 &&
          imageResponse.bodyBytes.isNotEmpty &&
          imageResponse.bodyBytes.length <= _maxImageBytes) {
        images.add(
          ActivityShareImage(
            bytes: Uint8List.fromList(imageResponse.bodyBytes),
            mimeType:
                _string(decoded['imageMimeType']) ??
                imageResponse.headers['content-type'] ??
                'image/jpeg',
            name: _string(decoded['imageName']),
          ),
        );
      }
    }
    final receivedAt = DateTime.tryParse(_string(decoded['receivedAt']) ?? '');
    final payload = ActivitySharePayload(
      sharedText: combinedText.isEmpty ? null : combinedText,
      sharedUrl: sharedUrl,
      images: images,
      sourceHint: _string(decoded['sourceHint']),
      receivedAt: receivedAt?.toLocal() ?? DateTime.now(),
    );
    if (!payload.hasData) return null;
    await http.delete(deleteUri);
    return payload;
  } on Object {
    return null;
  }
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
