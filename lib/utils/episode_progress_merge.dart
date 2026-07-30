/// Build a launch-time tracker snapshot keyed by `season_episode`.
///
/// Fully watched episodes win outright. Partial playback is meaningful above
/// five percent, only raises existing progress, and never downgrades a watched
/// episode. This is the same contract used by the merged series details page.
Map<String, double> buildEpisodeTrackerSnapshot({
  required Set<String> watched,
  required Map<String, double> playback,
}) {
  final merged = <String, double>{};

  for (final rawKey in watched) {
    final key = _normalizeEpisodeKey(rawKey);
    if (key != null) merged[key] = 100.0;
  }

  for (final entry in playback.entries) {
    final key = _normalizeEpisodeKey(entry.key);
    if (key == null || !entry.value.isFinite) continue;
    final progress = entry.value.clamp(0.0, 100.0).toDouble();
    final existing = merged[key] ?? 0.0;
    if (existing >= 100.0) continue;
    if (progress > 5.0 && progress > existing) {
      merged[key] = progress;
    }
  }

  return merged;
}

/// The furthest valid tracker percentage, or null when no tracker has data.
double? furthestEpisodeTrackerPercent(Iterable<double?> values) {
  double? best;
  for (final value in values) {
    if (value == null || !value.isFinite) continue;
    final clamped = value.clamp(0.0, 100.0).toDouble();
    if (best == null || clamped > best) best = clamped;
  }
  return best;
}

String? _normalizeEpisodeKey(String raw) {
  final match = RegExp(r'^(\d+)[_-](\d+)$').firstMatch(raw.trim());
  if (match == null) return null;
  return '${match.group(1)}_${match.group(2)}';
}
