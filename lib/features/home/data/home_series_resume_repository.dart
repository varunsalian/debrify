import '../../../models/advanced_search_selection.dart';
import '../../../models/custom_series_identity.dart';
import '../../../models/media_identity.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../models/home_series_resume_signals.dart';

/// Stateless reads for a captured profile. Each caller supplies its view guard
/// and already-loaded Trakt item; this repository owns no feed or resume cache.
class HomeSeriesResumeRepository {
  const HomeSeriesResumeRepository({
    required this.selectTraktItem,
    required this.readTraktShows,
    required this.resolveTraktShow,
    required this.readSimklPaused,
    required this.readSimklNext,
    required this.readLocalById,
    required this.readLocalByTitle,
    required this.isOwnerCurrent,
    required this.log,
  });

  final Future<AdvancedSearchSelection?> Function(
    TraktContinueWatchingItem,
    bool Function(),
  )
  selectTraktItem;
  final Future<List<TraktContinueWatchingItem>> Function() readTraktShows;
  final Future<AdvancedSearchSelection?> Function(String) resolveTraktShow;
  final Future<HomeSimklResumeSignal?> Function(String) readSimklPaused;
  final Future<({int season, int episode})?> Function(String) readSimklNext;
  final Future<Map<String, dynamic>?> Function(String) readLocalById;
  final Future<Map<String, dynamic>?> Function(String) readLocalByTitle;
  final bool Function() isOwnerCurrent;
  final void Function(String) log;

  bool _current(bool Function() isCurrent) => isOwnerCurrent() && isCurrent();

  /// Keep the full selection and the item's activity timestamp. Cached items
  /// resolve even before auth flags settle; only the live fallback is series-only.
  Future<HomeTraktResumeSignal?> traktSelection(
    StremioMeta item, {
    TraktContinueWatchingItem? cached,
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent)) return null;
    if (cached != null) {
      log(
        '[SeriesResume] trakt-home-card-hit title="${item.name}" '
        'lookupId=${item.progressId ?? item.id} cardId=${cached.id} '
        'card=S${cached.season}E${cached.episode} '
        'cardPct=${cached.progress} '
        'cardPausedAt=${_timestamp(cached.pausedAtMs)}',
      );
      final sel = await selectTraktItem(cached, () => _current(isCurrent));
      if (!_current(isCurrent) || sel == null) return null;
      log(
        '[SeriesResume] trakt-home-card-selection title="${item.name}" '
        'resolved=S${sel.season}E${sel.episode} '
        'resolvedPct=${sel.traktProgressPercent}',
      );
      return (sel: sel, tsMs: cached.pausedAtMs);
    }
    if (item.type != 'series') return null;
    final id = item.progressId ?? item.id;
    if (id.isEmpty) return null;
    // Fetch the item rather than resolving only coordinates: its timestamp
    // participates in recency ranking. Preserve exact first-match identity.
    final items = await readTraktShows();
    if (!_current(isCurrent)) return null;
    log(
      '[SeriesResume] trakt-live-lookup title="${item.name}" id=$id '
      'homeCacheMiss=true fetchedItems=${items.length}',
    );
    TraktContinueWatchingItem? selected;
    for (final it in items) {
      if (it.id == id) {
        selected = it;
        break;
      }
    }
    if (selected == null) return null;
    log(
      '[SeriesResume] trakt-live-match title="${item.name}" id=$id '
      'card=S${selected.season}E${selected.episode} '
      'cardPct=${selected.progress} '
      'cardPausedAt=${_timestamp(selected.pausedAtMs)}',
    );
    final sel = await selectTraktItem(selected, () => _current(isCurrent));
    if (!_current(isCurrent) || sel == null) return null;
    return (sel: sel, tsMs: selected.pausedAtMs);
  }

  /// The label's legacy resolver includes Trakt Up Next for uncached series.
  /// Uncached movies are handled by the separate movie-position reader. Never
  /// send an empty ID: the underlying resolver would choose an unrelated item.
  Future<HomeResumePosition?> traktPosition(
    StremioMeta item, {
    TraktContinueWatchingItem? cached,
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent)) return null;
    if (cached != null) {
      final sel = await selectTraktItem(cached, () => _current(isCurrent));
      if (!_current(isCurrent) || sel == null) return null;
      return (started: true, season: sel.season, episode: sel.episode);
    }
    if (item.type != 'series') return null;
    final id = item.progressId ?? item.id;
    if (id.isEmpty) return null;
    final sel = await resolveTraktShow(id);
    if (!_current(isCurrent) || sel == null) return null;
    return (started: true, season: sel.season, episode: sel.episode);
  }

  /// Native and custom progress identities must never fall back by title.
  Future<HomeLocalResumeSignal?> local(
    StremioMeta item,
    String playId, {
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent)) return null;
    Map<String, dynamic>? entry = await readLocalById(playId);
    if (!_current(isCurrent)) return null;
    var finished = entry?['finished'] == true;
    if (!MediaIdentity.isNative(playId) &&
        !CustomSeriesIdentity.isCustom(playId) &&
        (entry?['season'] is! int || entry?['episode'] is! int)) {
      entry = await readLocalByTitle(item.name);
      if (!_current(isCurrent)) return null;
      finished = entry?['finished'] == true;
    }
    final season = entry?['season'];
    final episode = entry?['episode'];
    if (season is! int || episode is! int) return null;
    // Series records use milliseconds; retain bare video fields as fallback.
    final pos = ((entry?['positionMs'] ?? entry?['position']) as num?)
        ?.toDouble();
    final dur = ((entry?['durationMs'] ?? entry?['duration']) as num?)
        ?.toDouble();
    final pct = (pos != null && dur != null && dur > 0)
        ? (pos / dur * 100).clamp(0.0, 100.0)
        : null;
    final tsMs = (entry?['updatedAt'] as num?)?.toInt();
    return (
      season: season,
      episode: episode,
      pct: pct,
      tsMs: tsMs != null && tsMs > 0 ? tsMs : null,
      finished: finished,
    );
  }

  /// The newest actual pause retains its timestamp for cross-source ranking.
  Future<HomeSimklResumeSignal?> simklPaused(
    StremioMeta item, {
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent) || item.type != 'series') return null;
    final id = item.progressId ?? item.id;
    if (id.isEmpty ||
        (!MediaIdentity.isImdb(id) && !MediaIdentity.isNative(id))) {
      return null;
    }
    final result = await readSimklPaused(id);
    return _current(isCurrent) ? result : null;
  }

  /// Server-computed next-to-watch is a weaker signal than an actual position.
  Future<({int season, int episode})?> simklNext(
    StremioMeta item, {
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent) || item.type != 'series') return null;
    final id = item.progressId ?? item.id;
    if (id.isEmpty ||
        (!MediaIdentity.isImdb(id) && !MediaIdentity.isNative(id))) {
      return null;
    }
    final result = await readSimklNext(id);
    return _current(isCurrent) ? result : null;
  }

  static String _timestamp(int? value) => value == null
      ? 'none'
      : DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
}
