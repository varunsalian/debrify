/// Minutes left from a '60 min'-shaped runtime and a 0..1 progress.
String? homeTonightTimeLeft(String? runtime, double? progress) {
  if (runtime == null || progress == null || progress <= 0) return null;
  final m = RegExp(r'(\d+)').firstMatch(runtime);
  if (m == null) return null;
  final total = int.tryParse(m.group(1)!);
  if (total == null || total <= 0) return null;
  final left = ((1 - progress.clamp(0.0, 1.0)) * total).round();
  return left <= 0 ? null : '$left min left';
}
