class ActivitySourceReference {
  const ActivitySourceReference({required this.ref, required this.url});

  final String ref;
  final String url;
}

ActivitySourceReference? extractStravaSourceReference(String? value) {
  final sourceUrl = value?.trim();
  if (sourceUrl == null || sourceUrl.isEmpty) return null;
  final uri = Uri.tryParse(sourceUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments
      .map(Uri.decodeComponent)
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);

  if (host == 'strava.app.link' || host.endsWith('.strava.app.link')) {
    if (segments.isEmpty) return null;
    return ActivitySourceReference(ref: segments.last.trim(), url: sourceUrl);
  }

  if (host == 'strava.com' || host.endsWith('.strava.com')) {
    final activitiesIndex = segments.indexWhere(
      (segment) => segment.toLowerCase() == 'activities',
    );
    if (activitiesIndex >= 0 && activitiesIndex + 1 < segments.length) {
      final activityId = segments[activitiesIndex + 1].trim();
      if (activityId.isNotEmpty) {
        return ActivitySourceReference(ref: activityId, url: sourceUrl);
      }
    }
  }
  return null;
}
