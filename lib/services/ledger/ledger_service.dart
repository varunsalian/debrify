import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:debrify/services/episode_tracker_snapshot_revision.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/ledger_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/features/ledger/models/ledger_media.dart';
import 'package:debrify/features/ledger/models/ledger_tracking.dart';
import 'ledger_api.dart';
import 'ledger_cache.dart';
import 'ledger_session.dart';

/// Account-wide watched state, read in one pass.
class LedgerWatchedSnapshot {
  const LedgerWatchedSnapshot({
    required this.movies,
    required this.showEpisodes,
    required this.showIds,
  });

  /// Lower-cased IMDb ids of watched movies.
  final Set<String> movies;

  /// Lower-cased show IMDb id → watched `"season_episode"` keys and when.
  final Map<String, Map<String, DateTime?>> showEpisodes;

  /// Lower-cased show IMDb id → catalog show id.
  final Map<String, String> showIds;
}

/// The app-facing Ledger tracker (placeholder name — see ledger_brand.dart).
///
/// Every read is failure-aware: null means "unknown", never "empty", so
/// callers keep their previous truth on a network error. Writes return
/// whether the server accepted them. Account-wide reads are cached briefly
/// per profile session and dropped on every write.
class LedgerService {
  LedgerService._(this.session, LedgerApi? api) {
    this.api = api ?? LedgerApi(tokens: session);
    session.onAccountChanged = _onAccountChanged;
  }

  static final LedgerService instance = LedgerService._(LedgerSession(), null);

  @visibleForTesting
  factory LedgerService.forTesting({
    required LedgerSession session,
    LedgerApi? api,
  }) => LedgerService._(session, api);

  final LedgerSession session;
  late final LedgerApi api;

  /// Bumped whenever this account's watched/progress state may have changed
  /// (a write, sign-in or sign-out). Home rows and badges listen to it.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final LedgerCache<LedgerWatchedSnapshot> _watched = LedgerCache(
    const Duration(seconds: 45),
  );
  final LedgerCache<List<LedgerPlayback>> _playback = LedgerCache(
    const Duration(seconds: 30),
  );
  final LedgerCache<List<LedgerUpNextEntry>> _upNext = LedgerCache(
    const Duration(seconds: 30),
  );
  final LedgerCache<Set<String>> _hidden = LedgerCache(
    const Duration(minutes: 5),
  );
  final LedgerCache<int> _finishPercent = LedgerCache(
    const Duration(minutes: 10),
  );

  /// The server's default watched percent.
  static const int defaultFinishPercent = 80;

  static const int _upNextPage = 100;
  static final RegExp _imdbPattern = RegExp(r'^tt[0-9]{1,12}$');

  /// The tracker only understands IMDb ids here; native (`simkl:`, custom)
  /// identities are skipped rather than sent as bogus items.
  static bool supportsId(String? imdbId) =>
      imdbId != null && _imdbPattern.hasMatch(imdbId.trim().toLowerCase());

  Future<bool> isAuthenticated({bool Function()? canContinue}) =>
      session.isAuthenticated(canContinue: canContinue);

  Future<String?> getUsername() => session.username();

  void _invalidate() {
    _watched.invalidate();
    _playback.invalidate();
    _upNext.invalidate();
    _hidden.invalidate();
    _finishPercent.invalidate();
  }

  void _onAccountChanged() {
    _invalidate();
    revision.value++;
  }

  void _afterWrite({String? showImdbId, bool announce = true}) {
    _invalidate();
    if (showImdbId != null) {
      EpisodeTrackerSnapshotRevision.invalidateTitle('ledger', showImdbId);
    }
    if (announce) {
      revision.value++;
      // Like the other trackers' writes: watched badges re-read once.
      MovieProgressStorage.movieFinishedRevision.value++;
    }
  }

  /// Drops everything owned by the outgoing profile.
  void resetProfileScope() {
    _invalidate();
    session.abandonPendingSignIns();
  }

  Future<void> signOut() => session.signOut();

  /// Drops the local session without revoking it server-side (app reset),
  /// matching how a reset treats Trakt.
  Future<void> forgetLocalSession() async {
    await LedgerStorage.clearAuth();
    _onAccountChanged();
  }

  // ── Reads ─────────────────────────────────────────────────────────────

  /// Runs [body] pinned to the profile active now, so a request's token
  /// reads, refresh and retry all stay in that profile even when the user
  /// switches profiles while it is out.
  static Future<T> _inOriginatingProfile<T>(Future<T> Function() body) =>
      ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
      ? ProfileRuntime.withCapturedScope(ProfileRuntime.capture(), body)
      : body();

  Future<T?> _guarded<T>(String label, Future<T> Function() body) async {
    try {
      return await _inOriginatingProfile(() async {
        if (!await session.isAuthenticated()) return null;
        return await body();
      });
    } on LedgerApiException catch (error) {
      debugPrint('Ledger: $label failed (${error.statusCode})');
      return null;
    } catch (error) {
      debugPrint('Ledger: $label error (${error.runtimeType})');
      return null;
    }
  }

  Future<LedgerWatchedSnapshot?> watchedSnapshot() => _watched.read(
    () => _guarded('watched', () async {
      final results = await Future.wait([
        api.watched(LedgerMediaKind.movie),
        api.watched(LedgerMediaKind.show),
      ]);
      final movies = <String>{
        for (final entry in results[0])
          if (entry.item.ids.imdb case final imdb?) imdb.toLowerCase(),
      };
      final shows = <String, Map<String, DateTime?>>{};
      final showIds = <String, String>{};
      for (final entry in results[1]) {
        final imdb = entry.item.ids.imdb?.toLowerCase();
        if (imdb == null) continue;
        if (entry.item.id case final id?) showIds[imdb] = id;
        final episodes = shows.putIfAbsent(imdb, () => <String, DateTime?>{});
        for (final episode in entry.episodes) {
          episodes['${episode.season}_${episode.episode}'] =
              episode.lastWatchedAt;
        }
      }
      return LedgerWatchedSnapshot(
        movies: Set.unmodifiable(movies),
        showEpisodes: Map.unmodifiable(shows),
        showIds: Map.unmodifiable(showIds),
      );
    }),
  );

  Future<List<LedgerPlayback>?> playback() =>
      _playback.read(() => _guarded('playback', () => api.playback()));

  Future<List<LedgerUpNextEntry>?> upNext() => _upNext.read(
    () => _guarded('up next', () => api.upNext(pageSize: _upNextPage)),
  );

  /// Shows Up Next leaves out on purpose: hidden from progress or dropped.
  Future<Set<String>?> _hiddenShows() => _hidden.read(
    () => _guarded('hidden', () async {
      final sections = await Future.wait([
        api.hidden('HIDDEN_SECTION_PROGRESS'),
        api.hidden('HIDDEN_SECTION_DROPPED'),
      ]);
      return <String>{
        for (final shows in sections)
          for (final show in shows)
            if (show.ids.imdb case final imdb?) imdb.toLowerCase(),
      };
    }),
  );

  /// The percent at which a STOP records a play for this account (50–100);
  /// [defaultFinishPercent] when unknown.
  Future<int> finishPercent() async =>
      await _finishPercent.read(
        () async => _guarded<int>(
          'tracking settings',
          () async =>
              await api.watchedPercent() ?? LedgerService.defaultFinishPercent,
        ),
      ) ??
      defaultFinishPercent;

  /// Watched movies and fully caught-up series (every aired regular episode
  /// played), as lower-cased IMDb ids.
  ///
  /// A watched show is caught up exactly when it has no Up Next entry: the
  /// server lists every show with an aired, unplayed regular episode unless
  /// it is hidden from progress or dropped. Specials don't count, so a show
  /// with only season 0 played is not caught up. When
  /// Up Next could be truncated (a full page) or a read failed, the series
  /// set is unknown and an empty set is reported rather than a guess.
  Future<({Set<String> movies, Set<String> series})?>
  fetchCompletedTitleIds() async {
    final snapshot = await watchedSnapshot();
    if (snapshot == null) return null;
    final upNext = await this.upNext();
    final hidden = await _hiddenShows();
    if (upNext == null || hidden == null || upNext.length >= _upNextPage) {
      return (movies: snapshot.movies, series: const <String>{});
    }
    final pending = <String>{
      for (final entry in upNext)
        if (entry.item.titleImdbId case final imdb?) imdb.toLowerCase(),
    };
    final series = <String>{
      for (final entry in snapshot.showEpisodes.entries)
        if (entry.value.keys.any((key) => !key.startsWith('0_')) &&
            !pending.contains(entry.key) &&
            !hidden.contains(entry.key))
          entry.key,
    };
    return (movies: snapshot.movies, series: Set.unmodifiable(series));
  }

  /// One show's episode states, read for that show only (no account-wide
  /// history): watched `"season_episode"` keys (specials included) and
  /// in-progress percents. Null when unknown; empty when the catalog does
  /// not hold the show yet.
  Future<({Set<String> watched, Map<String, double> progress})?>
  showEpisodeStates(String showImdbId) => _guarded('show progress', () async {
    final found = await api.status(LedgerMediaRef.show(showImdbId));
    final showId = found?.item?.id;
    if (showId == null) {
      return (watched: <String>{}, progress: <String, double>{});
    }
    final show = await api.showProgress(showId, includeSpecials: true);
    final watched = <String>{};
    final progress = <String, double>{};
    for (final episode in show?.episodes ?? const <LedgerEpisodeProgress>[]) {
      final key = '${episode.season}_${episode.episode}';
      if (episode.completed) watched.add(key);
      if (episode.progress case final percent?) progress[key] = percent;
    }
    return (watched: watched, progress: progress);
  });

  /// Watched `"season_episode"` keys for one show, null when unknown.
  Future<Set<String>?> watchedEpisodes(String showImdbId) async =>
      (await showEpisodeStates(showImdbId))?.watched;

  /// Watched `"season_episode"` → when, null when unknown.
  Future<Map<String, DateTime?>?> watchedEpisodeTimes(String showImdbId) async {
    final snapshot = await watchedSnapshot();
    if (snapshot == null) return null;
    return Map<String, DateTime?>.of(
      snapshot.showEpisodes[showImdbId.trim().toLowerCase()] ?? const {},
    );
  }

  /// In-progress episode percents for one show (`"season_episode"` → %).
  Future<Map<String, double>?> episodePlaybackProgress(
    String showImdbId,
  ) async {
    final all = await playback();
    if (all == null) return null;
    final target = showImdbId.trim().toLowerCase();
    final result = <String, double>{};
    final updated = <String, DateTime>{};
    for (final entry in all) {
      final item = entry.item;
      if (item.kind != LedgerMediaKind.episode) continue;
      if (item.show?.ids.imdb?.toLowerCase() != target) continue;
      final season = item.season;
      final number = item.number;
      if (season == null || number == null) continue;
      final key = '${season}_$number';
      final at = entry.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (updated[key] case final previous? when previous.isAfter(at)) {
        continue;
      }
      updated[key] = at;
      result[key] = entry.progress;
    }
    return result;
  }

  /// The most recently paused episode of a show, for "resume" labels.
  Future<({int season, int episode, double progress, DateTime? pausedAt})?>
  latestEpisodePlayback(String showImdbId) async {
    final all = await playback();
    if (all == null) return null;
    final target = showImdbId.trim().toLowerCase();
    LedgerPlayback? best;
    for (final entry in all) {
      final item = entry.item;
      if (item.kind != LedgerMediaKind.episode ||
          item.show?.ids.imdb?.toLowerCase() != target ||
          item.season == null ||
          item.number == null) {
        continue;
      }
      final at = entry.updatedAt;
      final bestAt = best?.updatedAt;
      if (best == null ||
          (at != null && (bestAt == null || at.isAfter(bestAt)))) {
        best = entry;
      }
    }
    if (best == null) return null;
    return (
      season: best.item.season!,
      episode: best.item.number!,
      progress: best.progress,
      pausedAt: best.updatedAt,
    );
  }

  /// Longest a launch waits for a movie's live resume point.
  static const Duration resumeReadTimeout = Duration(seconds: 3);

  /// A movie's saved resume point for a launch about to start (in-app or
  /// Android TV). Bounded by [resumeReadTimeout]: a slow or unreachable
  /// server never holds playback; the launch uses its other candidates.
  Future<double?> movieResumePercent(String? imdbId) async {
    if (!supportsId(imdbId)) return null;
    return moviePlaybackProgress(
      imdbId!,
    ).timeout(resumeReadTimeout, onTimeout: () => null);
  }

  Future<double?> moviePlaybackProgress(String imdbId) async {
    final all = await playback();
    if (all == null) return null;
    final target = imdbId.trim().toLowerCase();
    for (final entry in all) {
      if (entry.item.kind == LedgerMediaKind.movie &&
          entry.item.ids.imdb?.toLowerCase() == target) {
        return entry.progress;
      }
    }
    return null;
  }

  Future<LedgerItemStatus?> titleStatus(
    String imdbId,
    String contentType, {
    bool Function()? canContinue,
  }) async {
    if (!supportsId(imdbId) || canContinue?.call() == false) return null;
    final ref = contentType == 'series'
        ? LedgerMediaRef.show(imdbId)
        : LedgerMediaRef.movie(imdbId);
    final result = await _guarded('status', () => api.status(ref));
    if (canContinue?.call() == false) return null;
    return result?.status;
  }

  /// Whether every aired regular episode of the show has a play. Null when
  /// unknown; false when the catalog does not hold the show yet.
  Future<bool?> showCompleted(
    String showImdbId, {
    bool Function()? canContinue,
  }) async {
    if (!supportsId(showImdbId) || canContinue?.call() == false) return null;
    return _guarded('show completion', () async {
      final found = await api.status(LedgerMediaRef.show(showImdbId));
      final showId = found?.item?.id;
      if (showId == null) return false;
      final show = await api.showProgress(showId);
      return show != null &&
          show.airedEpisodes > 0 &&
          show.completedEpisodes >= show.airedEpisodes;
    });
  }

  // ── Writes ────────────────────────────────────────────────────────────

  Future<bool> _write(
    String label,
    Future<void> Function() body, {
    bool Function()? canContinue,
    String? showImdbId,
    bool announce = true,
  }) async {
    if (canContinue?.call() == false) return false;
    try {
      final sent = await _inOriginatingProfile(() async {
        if (!await session.isAuthenticated(canContinue: canContinue)) {
          return false;
        }
        if (canContinue?.call() == false) return false;
        await body();
        return true;
      });
      if (!sent) return false;
      _afterWrite(showImdbId: showImdbId, announce: announce);
      return true;
    } on LedgerApiException catch (error) {
      debugPrint('Ledger: $label failed (${error.statusCode})');
      return false;
    } catch (error) {
      debugPrint('Ledger: $label error (${error.runtimeType})');
      return false;
    }
  }

  static LedgerMediaRef _ref(String imdbId, int? season, int? episode) =>
      season != null && episode != null
      ? LedgerMediaRef.episode(imdbId, season, episode)
      : LedgerMediaRef.movie(imdbId);

  /// Sends one scrobble. A STOP at or past the user's watched percent
  /// records a play and clears the resume point server-side.
  Future<bool> scrobble(
    LedgerScrobbleAction action,
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) async {
    if (!supportsId(imdbId)) return false;
    return _write(
      'scrobble ${action.name}',
      () => api.scrobble(
        action: action,
        item: _ref(imdbId, season, episode),
        progress: progress,
      ),
      showImdbId: season == null ? null : imdbId,
      // Start/pause checkpoints during playback only refresh caches; a stop
      // is what changes rows and badges.
      announce: action == LedgerScrobbleAction.stop,
    );
  }

  Future<bool> markWatched(
    String imdbId,
    String contentType, {
    bool Function()? canContinue,
  }) => !supportsId(imdbId)
      ? Future.value(false)
      : _write(
          'mark watched',
          () => api.addHistory([
            contentType == 'series'
                ? LedgerMediaRef.show(imdbId)
                : LedgerMediaRef.movie(imdbId),
          ]),
          canContinue: canContinue,
          showImdbId: contentType == 'series' ? imdbId : null,
        );

  /// Removes every play of the title (a show: all of its episodes).
  Future<bool> markUnwatched(
    String imdbId,
    String contentType, {
    bool Function()? canContinue,
  }) => !supportsId(imdbId)
      ? Future.value(false)
      : _write(
          'mark unwatched',
          () => api.removeHistory([
            contentType == 'series'
                ? LedgerMediaRef.show(imdbId)
                : LedgerMediaRef.movie(imdbId),
          ]),
          canContinue: canContinue,
          showImdbId: contentType == 'series' ? imdbId : null,
        );

  Future<bool> markEpisodesWatched(
    String showImdbId,
    List<({int season, int episode})> episodes, {
    bool Function()? canContinue,
  }) => !supportsId(showImdbId) || episodes.isEmpty
      ? Future.value(false)
      : _write(
          'mark episodes watched',
          () => api.addHistory([
            for (final e in episodes)
              LedgerMediaRef.episode(showImdbId, e.season, e.episode),
          ]),
          canContinue: canContinue,
          showImdbId: showImdbId,
        );

  Future<bool> markEpisodesUnwatched(
    String showImdbId,
    List<({int season, int episode})> episodes, {
    bool Function()? canContinue,
  }) => !supportsId(showImdbId) || episodes.isEmpty
      ? Future.value(false)
      : _write(
          'mark episodes unwatched',
          () => api.removeHistory([
            for (final e in episodes)
              LedgerMediaRef.episode(showImdbId, e.season, e.episode),
          ]),
          canContinue: canContinue,
          showImdbId: showImdbId,
        );

  Future<bool> markSeason(
    String showImdbId,
    int season, {
    required bool watched,
    bool Function()? canContinue,
  }) => !supportsId(showImdbId)
      ? Future.value(false)
      : _write(
          watched ? 'mark season watched' : 'mark season unwatched',
          () => watched
              ? api.addHistory([LedgerMediaRef.season(showImdbId, season)])
              : api.removeHistory([LedgerMediaRef.season(showImdbId, season)]),
          canContinue: canContinue,
          showImdbId: showImdbId,
        );

  /// Deletes the saved resume point of a movie, or of one episode.
  Future<bool> deletePlayback(
    String imdbId, {
    int? season,
    int? episode,
    bool Function()? canContinue,
  }) async {
    if (!supportsId(imdbId) || canContinue?.call() == false) return false;
    final all = await playback();
    if (all == null || canContinue?.call() == false) return false;
    final target = imdbId.trim().toLowerCase();
    final ids = <String>[
      for (final entry in all)
        if (season == null
            ? entry.item.kind == LedgerMediaKind.movie &&
                  entry.item.ids.imdb?.toLowerCase() == target
            : entry.item.kind == LedgerMediaKind.episode &&
                  entry.item.show?.ids.imdb?.toLowerCase() == target &&
                  entry.item.season == season &&
                  entry.item.number == episode)
          entry.id,
    ];
    if (ids.isEmpty) return true;
    return _write(
      'delete playback',
      () async {
        for (final id in ids) {
          await api.deletePlayback(id);
        }
      },
      canContinue: canContinue,
      showImdbId: season == null ? null : imdbId,
    );
  }

  /// Removes a Continue Watching entry: its saved resume point when it has
  /// one, otherwise (a show's next episode) hides the show from Up Next.
  Future<bool> removeFromContinueWatching({
    required String imdbId,
    required bool isMovie,
    String? playbackId,
    bool Function()? canContinue,
  }) {
    if (!supportsId(imdbId)) return Future.value(false);
    if (isMovie) {
      if (playbackId == null) return Future.value(false);
      return _write(
        'remove continue watching',
        () => api.deletePlayback(playbackId),
        canContinue: canContinue,
      );
    }
    // A show would come straight back as its next episode, so it is also
    // hidden from Up Next (as Simkl's removal puts it On Hold).
    return _write(
      'hide from up next',
      () async {
        if (playbackId != null) await api.deletePlayback(playbackId);
        await api.hideFromProgress([LedgerMediaRef.show(imdbId)]);
      },
      canContinue: canContinue,
      showImdbId: imdbId,
    );
  }

  /// Marks the title dropped (it leaves Up Next), or takes the mark off.
  Future<bool> setDropped(
    String imdbId,
    String contentType, {
    required bool dropped,
    bool Function()? canContinue,
  }) {
    if (!supportsId(imdbId)) return Future.value(false);
    final ref = contentType == 'series'
        ? LedgerMediaRef.show(imdbId)
        : LedgerMediaRef.movie(imdbId);
    return _write(
      dropped ? 'drop' : 'undrop',
      () => api.setDropped([ref], dropped: dropped),
      canContinue: canContinue,
      showImdbId: contentType == 'series' ? imdbId : null,
    );
  }

  /// Removes every play of the title and its saved resume points (a show:
  /// those of all its episodes).
  Future<bool> clearProgress(
    String imdbId,
    String contentType, {
    bool Function()? canContinue,
  }) async {
    if (!supportsId(imdbId)) return false;
    final series = contentType == 'series';
    final target = imdbId.trim().toLowerCase();
    final showImdbId = series ? imdbId : null;
    // Two writes, so plays that were removed refresh caches and badges even
    // when clearing the resume points then fails. Announced once, at the end.
    final plays = await _write(
      'clear plays',
      () => api.removeHistory([
        series ? LedgerMediaRef.show(imdbId) : LedgerMediaRef.movie(imdbId),
      ]),
      canContinue: canContinue,
      showImdbId: showImdbId,
      announce: false,
    );
    if (!plays) return false;
    final points = await _write(
      'clear resume points',
      () async {
        final kind = series ? LedgerMediaKind.episode : LedgerMediaKind.movie;
        for (final entry in await api.playback(kind: kind)) {
          if (entry.item.titleImdbId?.toLowerCase() == target) {
            await api.deletePlayback(entry.id);
          }
        }
      },
      canContinue: canContinue,
      showImdbId: showImdbId,
      announce: false,
    );
    _afterWrite(showImdbId: showImdbId);
    return points;
  }

  Future<bool> setWatchlisted(
    String imdbId,
    String contentType, {
    required bool listed,
    bool Function()? canContinue,
  }) {
    if (!supportsId(imdbId)) return Future.value(false);
    final ref = contentType == 'series'
        ? LedgerMediaRef.show(imdbId)
        : LedgerMediaRef.movie(imdbId);
    return _write(
      listed ? 'watchlist add' : 'watchlist remove',
      () => listed ? api.addToWatchlist([ref]) : api.removeFromWatchlist([ref]),
      canContinue: canContinue,
    );
  }

  Future<bool> rate(
    String imdbId,
    String contentType,
    int? rating, {
    bool Function()? canContinue,
  }) {
    if (!supportsId(imdbId)) return Future.value(false);
    final ref = contentType == 'series'
        ? LedgerMediaRef.show(imdbId)
        : LedgerMediaRef.movie(imdbId);
    return _write(
      rating == null ? 'remove rating' : 'rate',
      () => rating == null ? api.removeRating(ref) : api.rate(ref, rating),
      canContinue: canContinue,
    );
  }
}
