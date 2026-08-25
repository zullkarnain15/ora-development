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
