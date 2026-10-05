import 'dart:math';

String formatDebrifyTvBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final exponent = min(units.length - 1, (log(bytes) / log(1024)).floor());
  final value = bytes / pow(1024, exponent);
  final formatted = value >= 10
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[exponent]}';
}
