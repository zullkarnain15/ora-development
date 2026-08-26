import 'dart:typed_data';

enum ActivityImportSource {
  strava,
  garmin,
  coros,
  suunto,
  huawei,
  amazfit,
  unknown,
}

extension ActivityImportSourceValue on ActivityImportSource {
  String get label => name.toUpperCase();

  static ActivityImportSource parse(String? value) =>
      switch (value?.trim().toUpperCase()) {
        'STRAVA' => ActivityImportSource.strava,
        'GARMIN' => ActivityImportSource.garmin,
        'COROS' => ActivityImportSource.coros,
        'SUUNTO' => ActivityImportSource.suunto,
        'HUAWEI' => ActivityImportSource.huawei,
        'AMAZFIT' => ActivityImportSource.amazfit,
        _ => ActivityImportSource.unknown,
      };
}

class ActivityShareImage {
  const ActivityShareImage({
    required this.bytes,
    required this.mimeType,
    this.name,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? name;

  ActivityShareImage normalized() {
    final normalizedMimeType = detectActivityImageMimeType(bytes, mimeType);
    final normalizedName = normalizeActivityImageName(name, normalizedMimeType);
    if (normalizedMimeType == mimeType && normalizedName == name) return this;
    return ActivityShareImage(
      bytes: bytes,
      mimeType: normalizedMimeType,
      name: normalizedName,
    );
  }
}

String detectActivityImageMimeType(Uint8List bytes, String declaredMimeType) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6) {
    final header = String.fromCharCodes(bytes.take(6));
    if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.skip(0).take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.skip(4).take(4)) == 'ftyp') {
    final brand = String.fromCharCodes(bytes.skip(8).take(4)).toLowerCase();
    if (brand == 'avif' || brand == 'avis') return 'image/avif';
    if ({'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'}.contains(brand)) {
      return 'image/heic';
    }
  }
  final declared = declaredMimeType.split(';').first.trim().toLowerCase();
  return declared.startsWith('image/') ? declared : 'image/jpeg';
}

String? normalizeActivityImageName(String? name, String mimeType) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final extension = switch (mimeType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/avif' => 'avif',
    'image/heic' => 'heic',
    _ => null,
  };
  if (extension == null) return trimmed;
  final dot = trimmed.lastIndexOf('.');
  final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
  return '$base.$extension';
}

class ActivitySharePayload {
  const ActivitySharePayload({
    this.sharedText,
    this.sharedUrl,
    this.images = const [],
    this.sourceHint,
    this.transientImageId,
    required this.receivedAt,
  });

  final String? sharedText;
  final String? sharedUrl;
  final List<ActivityShareImage> images;
  final String? sourceHint;
  final String? transientImageId;
  final DateTime receivedAt;

  bool get hasData =>
      (sharedText?.trim().isNotEmpty ?? false) ||
      (sharedUrl?.trim().isNotEmpty ?? false) ||
      images.isNotEmpty;

  ActivitySharePayload copyWith({
    String? sharedText,
    String? sharedUrl,
    List<ActivityShareImage>? images,
    String? sourceHint,
    String? transientImageId,
    bool clearTransientImageId = false,
  }) => ActivitySharePayload(
    sharedText: sharedText ?? this.sharedText,
    sharedUrl: sharedUrl ?? this.sharedUrl,
    images: images ?? this.images,
    sourceHint: sourceHint ?? this.sourceHint,
    transientImageId: clearTransientImageId
        ? null
        : transientImageId ?? this.transientImageId,
    receivedAt: receivedAt,
  );
}
