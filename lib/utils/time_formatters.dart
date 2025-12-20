/// Formats a Duration into a human-readable time string (HH:MM:SS or MM:SS)
String formatDuration(Duration d) {
  final sign = d.isNegative ? '-' : '';
  final abs = d.abs();
  final h = abs.inHours;
  final m = abs.inMinutes % 60;
  final s = abs.inSeconds % 60;
  if (h > 0) {
    return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
