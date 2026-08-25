import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../domain/activity_share_payload.dart';

const _maxImageBytes = 10 * 1024 * 1024;
final _validShareId = RegExp(r'^[a-zA-Z0-9-]+$');
JSFunction? _messageHandler;

Future<ActivitySharePayload?> readPlatformWebShareTargetPayload(Uri uri) async {
  if (uri.queryParameters['share_target'] != '1') return null;
  final shareId = uri.queryParameters['share_id']?.trim();
  if (shareId == null || !_validShareId.hasMatch(shareId)) return null;
  return _readPayload(uri, shareId);
}

Future<ActivitySharePayload?> _readPayload(Uri uri, String shareId) async {
  final metadataUri = uri.resolve('_ora_share_payload/$shareId.json');
  final imageUri = uri.resolve('_ora_share_payload/$shareId.image');
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
    return payload;
  } on Object {
    return null;
  }
}

void startPlatformWebShareTargetListener(
  Future<void> Function(ActivitySharePayload payload) onPayload,
) {
  stopPlatformWebShareTargetListener();
  final serviceWorker = web.window.navigator.serviceWorker;
  _messageHandler = ((web.MessageEvent event) {
    final data = event.data?.dartify();
    if (data is! Map) return;
    final type = data['type'];
    if (type == 'ORA_ACTIVITY_SHARE') {
      final shareId = data['shareId'];
      if (shareId is! String || !_validShareId.hasMatch(shareId)) return;
      unawaited(_deliverPayload(Uri.base, shareId, onPayload));
    } else if (type == 'ORA_ACTIVITY_SHARE_ERROR') {
      final error = data['error'];
      unawaited(onPayload(_errorPayload(error is String ? error : null)));
    }
  }).toJS;
  serviceWorker.onmessage = _messageHandler;
  serviceWorker.startMessages();
}

Future<void> _deliverPayload(
  Uri uri,
  String shareId,
  Future<void> Function(ActivitySharePayload payload) onPayload,
) async {
  final payload = await _readPayload(uri, shareId);
  if (payload != null) await onPayload(payload);
}

void stopPlatformWebShareTargetListener() {
  if (_messageHandler == null) return;
  web.window.navigator.serviceWorker.onmessage = null;
  _messageHandler = null;
}

ActivitySharePayload _errorPayload(String? code) => ActivitySharePayload(
  sharedText: switch (code) {
    'too_large' => 'STRAVA IMAGE IS LARGER THAN 10 MB',
    'empty' => 'STRAVA SHARE DID NOT INCLUDE AN IMAGE, TEXT, OR URL',
    _ => 'STRAVA SHARE COULD NOT BE READ',
  },
  sourceHint: 'STRAVA',
  receivedAt: DateTime.now(),
);

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
