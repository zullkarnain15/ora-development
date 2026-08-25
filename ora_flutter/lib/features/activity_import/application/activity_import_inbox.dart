import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/activity_import_launch_store.dart';
import '../domain/activity_share_payload.dart';

class ActivityImportLaunch {
  const ActivityImportLaunch({this.token, this.payload, this.manual = false});

  final String? token;
  final ActivitySharePayload? payload;
  final bool manual;

  bool get hasRequest =>
      manual || (token?.isNotEmpty ?? false) || (payload?.hasData ?? false);

  Map<String, Object?> toJson() => {
    'token': token,
    'manual': manual,
    'sharedText': payload?.sharedText,
    'sharedUrl': payload?.sharedUrl,
    'sourceHint': payload?.sourceHint,
    'receivedAt': payload?.receivedAt.toUtc().toIso8601String(),
  };

  factory ActivityImportLaunch.fromJson(Map<String, Object?> json) {
    final receivedAt = DateTime.tryParse(_string(json['receivedAt']) ?? '');
    final payload = ActivitySharePayload(
      sharedText: _string(json['sharedText']),
      sharedUrl: _string(json['sharedUrl']),
      sourceHint: _string(json['sourceHint']),
      receivedAt: receivedAt?.toLocal() ?? DateTime.now(),
    );
    return ActivityImportLaunch(
      token: _string(json['token']),
      manual: json['manual'] == true,
      payload: payload.hasData ? payload : null,
    );
  }

  static ActivityImportLaunch? fromUri(Uri uri) {
    final fragmentUri = uri.fragment.isEmpty
        ? null
        : Uri.tryParse(
            uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}',
          );
    final token =
        _string(uri.queryParameters['t']) ??
        _string(fragmentUri?.queryParameters['t']);
    final isImportPath = fragmentUri?.path.startsWith('/import') == true;
    final isShareTarget = uri.queryParameters['share_target'] == '1';
    if (token == null && !isImportPath && !isShareTarget) return null;

    final title = _string(uri.queryParameters['title']);
    final text = _string(uri.queryParameters['text']);
    final url = _string(uri.queryParameters['url']);
    final combinedText = [?title, ?text].join('\n');
    final payload = ActivitySharePayload(
      sharedText: combinedText.isEmpty ? null : combinedText,
      sharedUrl: url,
      receivedAt: DateTime.now(),
    );
    return ActivityImportLaunch(
      token: token,
      payload: payload.hasData ? payload : null,
      manual: token == null && !payload.hasData,
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class ActivityImportInbox extends ChangeNotifier {
  ActivityImportInbox({ActivityImportLaunchStore? store})
    : _store = store ?? createActivityImportLaunchStore();

  static const _channel = MethodChannel('ora/activity_share');
  final ActivityImportLaunchStore _store;
  ActivityImportLaunch? current;
  bool _disposed = false;

  Future<void> initialize() async {
    final stored = await _store.load();
    if (stored != null) current = ActivityImportLaunch.fromJson(stored);

    final launched = ActivityImportLaunch.fromUri(Uri.base);
    if (launched?.hasRequest == true) await receive(launched!);

    if (!kIsWeb) {
      _channel.setMethodCallHandler(_handleNativeCall);
      try {
        final initial = await _channel.invokeMapMethod<String, Object?>(
          'getInitialSharePayload',
        );
        if (initial != null) await _receiveNativeMap(initial);
      } on MissingPluginException {
        // Platform has no native share adapter; manual import remains available.
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> receive(ActivityImportLaunch launch) async {
    if (!launch.hasRequest) return;
    current = launch;
    if (launch.payload?.images.isEmpty != false) {
      await _store.save(launch.toJson());
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> openManual() => receive(
    ActivityImportLaunch(
      manual: true,
      payload: ActivitySharePayload(receivedAt: DateTime.now()),
    ),
  );

  Future<void> clear() async {
    current = null;
    await _store.clear();
    if (!_disposed) notifyListeners();
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onSharePayload') return null;
    final arguments = call.arguments;
    if (arguments is Map) {
      await _receiveNativeMap(
        arguments.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  Future<void> _receiveNativeMap(Map<String, Object?> value) async {
    final bytes = value['imageBytes'];
    final images = <ActivityShareImage>[];
    if (bytes is Uint8List) {
      images.add(
        ActivityShareImage(
          bytes: bytes,
          mimeType:
              ActivityImportLaunch._string(value['imageMimeType']) ??
              'image/jpeg',
          name: ActivityImportLaunch._string(value['imageName']),
        ),
      );
    }
    final payload = ActivitySharePayload(
      sharedText: ActivityImportLaunch._string(value['sharedText']),
      sharedUrl: ActivityImportLaunch._string(value['sharedUrl']),
      sourceHint: ActivityImportLaunch._string(value['sourceHint']),
      images: images,
      receivedAt: DateTime.now(),
    );
    if (payload.hasData) await receive(ActivityImportLaunch(payload: payload));
  }

  @override
  void dispose() {
    _disposed = true;
    if (!kIsWeb) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
