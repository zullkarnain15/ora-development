String formatDistanceMeters(double meters) =>
    '${(meters / 1000).clamp(0, double.infinity).toStringAsFixed(2)} KM';

String formatBackendDistance(double km) =>
    '${km.clamp(0, double.infinity).toStringAsFixed(2)} KM';

String formatDurationMillis(int millis) {
  final seconds = (millis < 0 ? 0 : millis) ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String formatPace(int? seconds) {
  if (seconds == null || seconds <= 0) return '--:-- /KM';
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')} /KM';
}

String formatActivityDate(int epochMillis) {
  final value = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${months[value.month - 1]} ${value.day.toString().padLeft(2, '0')} - '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String compactNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
