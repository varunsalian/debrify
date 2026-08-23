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

/// Whether Trakt currently describes an active rewatch for an episode.
///
/// Older player builds copied Trakt's watched history into the local finished
/// and resume stores. Those writes did not carry provenance, so deleting them
/// during migration could erase a genuine local completion. A current partial
/// Trakt playback is the one unambiguous signal that the old completed value is
/// stale for *display and resume*. Simkl or MDBList completion still wins: it
/// is independent provider evidence that the episode remains completed.
bool hasActiveTraktEpisodeRewatch({
  required double? traktPercent,
  required double? simklPercent,
  required double? mdblistPercent,
  double completionThreshold = 95.0,
}) {
  double? normalized(double? value) {
    if (value == null || !value.isFinite) return null;
    return value.clamp(0.0, 100.0).toDouble();
  }

  final trakt = normalized(traktPercent);
  if (trakt == null || trakt <= 0.0 || trakt >= completionThreshold) {
    return false;
  }
  final simkl = normalized(simklPercent) ?? 0.0;
  final mdblist = normalized(mdblistPercent) ?? 0.0;
  return simkl < completionThreshold && mdblist < completionThreshold;
}

/// Resolve local guide state in the presence of a current Trakt rewatch.
///
/// This is deliberately non-destructive: the legacy seed is indistinguishable
/// from genuine local history on disk. We suppress the completed bit in the
/// rendered/native snapshot, and clear only an already-complete position from
/// that snapshot so the partial tracker position can drive resume. A genuine
/// in-progress local position is retained and can still win by being further.
({bool watched, int positionMs}) resolveEpisodeLocalWatchState({
  required bool locallyWatched,
  required int localPositionMs,
  required int localDurationMs,
  required double? traktPercent,
  required double? simklPercent,
  required double? mdblistPercent,
  double completionThreshold = 95.0,
}) {
  final rewatch = hasActiveTraktEpisodeRewatch(
    traktPercent: traktPercent,
    simklPercent: simklPercent,
    mdblistPercent: mdblistPercent,
    completionThreshold: completionThreshold,
  );
  if (!rewatch) {
    return (watched: locallyWatched, positionMs: localPositionMs);
  }

  final localPercent = localDurationMs > 0
      ? localPositionMs * 100.0 / localDurationMs
      : 0.0;
  return (
    watched: false,
    positionMs: localPercent >= completionThreshold ? 0 : localPositionMs,
  );
}

typedef EpisodeCoordinate = ({int season, int episode});

/// Resolve the visual "up next" episode from the already-merged progress map.
///
/// A partially watched episode is the strongest signal because it represents
/// an active session from any connected tracker. Otherwise an unfinished
/// tracker suggestion is retained, falling forward when that suggestion has
/// since become watched. This keeps the badge consistent with the same merged
/// state that draws watched ticks and progress bars.
EpisodeCoordinate? mergedEpisodeUpNext({
  required Iterable<EpisodeCoordinate> episodes,
  required Map<String, double> progress,
  EpisodeCoordinate? trackerNext,
}) {
  final ordered = episodes.toList(growable: false);
  if (ordered.isEmpty) return null;

  double progressFor(EpisodeCoordinate episode) =>
      progress['${episode.season}-${episode.episode}'] ??
      progress['${episode.season}_${episode.episode}'] ??
      0.0;

  EpisodeCoordinate? partial;
  for (final episode in ordered) {
    final value = progressFor(episode);
    if (value > 0.0 && value < 100.0) partial = episode;
  }
  if (partial != null) return partial;

  if (trackerNext != null) {
    final trackerIndex = ordered.indexWhere(
      (episode) =>
          episode.season == trackerNext.season &&
          episode.episode == trackerNext.episode,
    );
    if (trackerIndex >= 0) {
      if (progressFor(ordered[trackerIndex]) < 100.0) {
        return ordered[trackerIndex];
      }
      for (var index = trackerIndex + 1; index < ordered.length; index++) {
        if (progressFor(ordered[index]) < 100.0) return ordered[index];
      }
    }
  }

  for (final episode in ordered) {
    if (progressFor(episode) < 100.0) return episode;
  }
  return null;
}

String? _normalizeEpisodeKey(String raw) {
  final match = RegExp(r'^(\d+)[_-](\d+)$').firstMatch(raw.trim());
  if (match == null) return null;
  return '${match.group(1)}_${match.group(2)}';
}
