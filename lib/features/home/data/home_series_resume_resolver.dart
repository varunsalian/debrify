import '../../../models/advanced_search_selection.dart';
import '../../../models/mdblist_continue_watching.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../../../services/tracking_source_policy.dart';
import '../models/home_series_resume_result.dart';
import '../models/home_series_resume_signals.dart';
import 'home_series_resume_repository.dart';
import 'home_series_resume_resolution.dart';
import 'home_tracker_resume_repository.dart';
import 'home_tracking_policy_repository.dart';

/// One view's shared answer for its detail Resume label and Play action.
/// Services own their transport/caches; this owner retains only reconciled results.
class HomeSeriesResumeResolver {
  HomeSeriesResumeResolver({
    required this.signals,
    required this.trackers,
    required this.policies,
    required this.findNextEpisode,
    required this.readRevision,
    required this.isOwnerCurrent,
    required this.now,
    required this.log,
  });

  final HomeSeriesResumeRepository signals;
  final HomeTrackerResumeRepository trackers;
  final HomeTrackingPolicyRepository policies;
  final Future<({int season, int episode})?> Function(
    String id,
    int season,
    int episode, {
    required bool preferBuiltIn,
    StremioMeta? catalogItem,
  })
  findNextEpisode;
  final int Function(String provider, String id) readRevision;
  final bool Function() isOwnerCurrent;
  final DateTime Function() now;
  final void Function(String) log;
  final Map<String, ({int atMs, String rev, HomeSeriesResumeResult r})> _cache =
      {};
  static const _maxCachedResults = 512;
  int _generation = 0;
  bool _disposed = false;

  void clear() {
    if (_disposed) return;
    _generation++;
    _cache.clear();
  }

  void dispose() {
    clear();
    _disposed = true;
  }

  String _seriesResumeRev(
    String id,
    bool isTraktSource,
    WatchProgressSource progress,
    HomeResumeAvailability available,
  ) =>
      '${readRevision('trakt', id)}.'
      '${readRevision('simkl', id)}.'
      '${readRevision('mdblist', id)}.'
      '${readRevision('local', id)}.'
      '${available.trakt ? 1 : 0}${available.simkl ? 1 : 0}'
      '${available.mdblist ? 1 : 0}${isTraktSource ? 1 : 0}.'
      '${progress.name}';

  /// Null means cancellation, never an unstarted S1E1 launch. Availability and
  /// cached card reads stay lazy, after the fresh tracking-policy load.
  Future<HomeSeriesResumeResult?> resolve(
    StremioMeta item, {
    required HomeResumeAvailability Function() availability,
    required TraktContinueWatchingItem? Function() cachedTrakt,
    required bool Function() isCurrent,
    bool isTraktSource = false,
    bool preferBuiltIn = false,
    StremioMeta? catalogItem,
  }) async {
    final generation = _generation;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        isOwnerCurrent() &&
        isCurrent();
    if (!current()) return null;
    final trackingPolicy = await policies.loadForContent(
      item.progressId,
      isCurrent: current,
    );
    if (!current() || trackingPolicy == null) return null;
    final available = availability();
    final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    final playId = ttId.isNotEmpty ? ttId : (item.progressId ?? item.id);
    final nowMs = now().millisecondsSinceEpoch;
    final progressRev = _seriesResumeRev(
      playId,
      isTraktSource,
      trackingPolicy.progressSource,
      available,
    );
    final rev =
        '$progressRev:$preferBuiltIn:${catalogItem?.sourceAddon?.sourceBindingKey}:${catalogItem?.id}';
    final hit = _cache[playId];
    if (hit != null && nowMs - hit.atMs < 45000 && hit.rev == rev) {
      log(
        '[SeriesResume] reconcile-cache-hit title="${item.name}" '
        'id=$playId ageMs=${nowMs - hit.atMs} rev=$rev '
        'result=S${hit.r.season}E${hit.r.episode} '
        'started=${hit.r.started} source=${sourceName(hit.r.sourcePrio)}',
      );
      _cache.remove(playId);
      _cache[playId] = hit;
      return hit.r;
    }
    log(
      '[SeriesResume] reconcile-start title="${item.name}" id=$playId '
      'rawId=${item.id} effectiveId=${item.progressId} '
      'traktAuth=${available.trakt} simklAuth=${available.simkl} '
      'mdblistAuth=${available.mdblist} traktSource=$isTraktSource '
      'rev=$rev cache=${hit == null ? 'miss' : 'stale-or-revised'}',
    );
    _cache.removeWhere((_, v) => nowMs - v.atMs >= 45000);

    // Kick everything off together; a degraded tracker API must never stall
    // the Play press (same 4s boxes the old chain used).
    final traktF = _observe<HomeTraktResumeSignal?>(
      trackingPolicy.progressFrom(TrackingSource.trakt) &&
              (available.trakt || isTraktSource)
          ? signals
                .traktSelection(item, cached: cachedTrakt(), isCurrent: current)
                .timeout(const Duration(seconds: 4), onTimeout: () => null)
          : Future.value(null),
    );
    final simklF = _observe<HomeSimklResumeSignal?>(
      trackingPolicy.progressFrom(TrackingSource.simkl) && available.simkl
          ? signals
                .simklPaused(item, isCurrent: current)
                .timeout(const Duration(seconds: 4), onTimeout: () => null)
          : Future.value(null),
    );
    final mdbF = _observe<MdblistContinueWatchingItem?>(
      trackingPolicy.progressFrom(TrackingSource.mdblist) && available.mdblist
          ? trackers
                .mdblistItem(item.progressId ?? item.id, isCurrent: current)
                .timeout(const Duration(seconds: 4), onTimeout: () => null)
          : Future.value(null),
    );
    final localF = _observe<HomeLocalResumeSignal?>(
      trackingPolicy.progressFrom(TrackingSource.local)
          ? signals.local(item, playId, isCurrent: current)
          : Future.value(null),
    );
    final nextF = _observe<({int season, int episode})?>(
      trackingPolicy.progressFrom(TrackingSource.simkl) && available.simkl
          ? signals
                .simklNext(item, isCurrent: current)
                .timeout(const Duration(seconds: 4), onTimeout: () => null)
          : Future.value(null),
    );

    // Observe every started future immediately, including those left running
    // after cancellation/error. Unwrap in the original order so active failures
    // keep their caller-visible precedence and stack; no retry is introduced.
    final traktRead = await traktF;
    if (!current()) return null;
    final trakt = traktRead.unwrap();
    final simklRead = await simklF;
    if (!current()) return null;
    final simkl = simklRead.unwrap();
    final mdbRead = await mdbF;
    if (!current()) return null;
    final mdb = mdbRead.unwrap();
    final localRead = await localF;
    if (!current()) return null;
    final local = localRead.unwrap();
    final nextRead = await nextF;
    if (!current()) return null;
    final simklNext = nextRead.unwrap();

    log(
      '[SeriesResume] reconcile-inputs title="${item.name}" id=$playId '
      'trakt=${_formatTraktResume(trakt)} '
      'simkl=${_formatSimklResume(simkl)} '
      'mdblist=${_formatMdblistResume(mdb)} '
      'local=${_formatLocalResume(local)} '
      'simklNext=${simklNext == null ? 'none' : 'S${simklNext.season}E${simklNext.episode}'}',
    );

    final result = await resolveHomeSeriesResume(
      trakt: trakt,
      simkl: simkl,
      mdb: mdb,
      local: local,
      simklNext: simklNext,
      findNextEpisode: (season, episode) => !current()
          ? Future.value(null)
          : findNextEpisode(
              playId,
              season,
              episode,
              preferBuiltIn: preferBuiltIn,
              catalogItem: catalogItem,
            ),
      onWinner: (winner, {required trackerFrontierAhead, required willAdvance}) {
        if (!current()) return;
        log(
          '[SeriesResume] reconcile-winner title="${item.name}" id=$playId '
          'source=${sourceName(winner.sourcePriority)} base=S${winner.season}E${winner.episode} '
          'pct=${winner.progress} timestamp=${_formatResumeTimestamp(winner.timestampMs)} '
          'finished=${winner.finished} trackerFrontierAhead=$trackerFrontierAhead '
          'willAdvance=$willAdvance '
          'progressPolicy=${trackingPolicy.progressSource.name}',
        );
      },
      onAdvance: (from, next, adjacentTrackerFrontier, target) {
        if (!current()) return;
        log(
          '[SeriesResume] reconcile-advance title="${item.name}" id=$playId '
          'guideNext=${next == null ? 'none' : 'S${next.season}E${next.episode}'} '
          'adjacentTracker=${adjacentTrackerFrontier == null ? 'none' : 'S${adjacentTrackerFrontier.season}E${adjacentTrackerFrontier.episode}'} '
          'chosen=${target == null ? 'keep-S${from.season}E${from.episode}' : 'S${target.season}E${target.episode}'}',
        );
      },
    );
    if (!current()) return null;
    log(
      '[SeriesResume] reconcile-result title="${item.name}" id=$playId '
      'started=${result.started} target=S${result.season}E${result.episode} '
      'source=${sourceName(result.sourcePrio)} '
      'hasOriginalSelection=${result.selection != null} '
      'simklPct=${result.simklProgress}',
    );
    // Bound retained detail answers without renewing their 45-second lifetime.
    _cache.remove(playId);
    _cache[playId] = (atMs: nowMs, rev: rev, r: result);
    while (_cache.length > _maxCachedResults) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  static String sourceName(int? priority) => switch (priority) {
    0 => 'trakt',
    1 => 'simkl',
    2 => 'mdblist',
    3 => 'local',
    _ => 'fallback',
  };

  String _formatResumeTimestamp(int? timestampMs) {
    if (timestampMs == null) return 'none';
    return DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String();
  }

  String _formatTraktResume(({AdvancedSearchSelection sel, int? tsMs})? value) {
    if (value == null) return 'none';
    return 'S${value.sel.season}E${value.sel.episode}'
        '/pct=${value.sel.traktProgressPercent}'
        '/at=${_formatResumeTimestamp(value.tsMs)}';
  }

  String _formatSimklResume(
    ({int season, int episode, double? progress, DateTime? pausedAt})? value,
  ) {
    if (value == null) return 'none';
    return 'S${value.season}E${value.episode}'
        '/pct=${value.progress}'
        '/at=${value.pausedAt?.toIso8601String() ?? 'none'}';
  }

  String _formatMdblistResume(MdblistContinueWatchingItem? value) {
    if (value == null) return 'none';
    return 'S${value.selection.season}E${value.selection.episode}'
        '/pct=${value.selection.mdblistProgressPercent}'
        '/paused=${value.paused}'
        '/at=${value.updatedAt?.toIso8601String() ?? 'none'}';
  }

  String _formatLocalResume(
    ({int season, int episode, double? pct, int? tsMs, bool finished})? value,
  ) {
    if (value == null) return 'none';
    return 'S${value.season}E${value.episode}'
        '/pct=${value.pct}'
        '/finished=${value.finished}'
        '/at=${_formatResumeTimestamp(value.tsMs)}';
  }

  static Future<_ResumeRead<T>> _observe<T>(Future<T> work) async {
    try {
      return _ResumeRead.value(await work);
    } catch (error, stack) {
      return _ResumeRead.error(error, stack);
    }
  }
}

class _ResumeRead<T> {
  const _ResumeRead.value(this.value) : error = null, stack = null;
  const _ResumeRead.error(this.error, this.stack) : value = null;
  final T? value;
  final Object? error;
  final StackTrace? stack;

  T unwrap() {
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return value as T;
  }
}
