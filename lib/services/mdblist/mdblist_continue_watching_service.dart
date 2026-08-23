import '../../models/advanced_search_selection.dart';
import 'package:flutter/foundation.dart';

import 'mdblist_models.dart';
import 'mdblist_service.dart';

class MdblistContinueWatchingItem {
  final AdvancedSearchSelection selection;
  final int? playbackId;
  final bool paused;
  final DateTime? updatedAt;
  final MdblistScrobbleTarget? clearTarget;

  const MdblistContinueWatchingItem({
    required this.selection,
    required this.paused,
    this.playbackId,
    this.updatedAt,
    this.clearTarget,
  });
}

class MdblistContinueWatchingSnapshot {
  final List<MdblistContinueWatchingItem> movies;
  final List<MdblistContinueWatchingItem> shows;

  const MdblistContinueWatchingSnapshot({
    this.movies = const [],
    this.shows = const [],
  });
}

class MdblistContinueWatchingService {
  final MdblistService service;
  MdblistContinueWatchingSnapshot? _lastGood;
  DateTime? _lastFetchedAt;
  int _cacheGeneration = 0;

  MdblistContinueWatchingService._(this.service);
  factory MdblistContinueWatchingService.forTesting(MdblistService service) =>
      MdblistContinueWatchingService._(service);
  static final MdblistContinueWatchingService instance =
      MdblistContinueWatchingService._(MdblistService.instance);

  void resetProfileScope() {
    _cacheGeneration++;
    _lastGood = null;
    _lastFetchedAt = null;
  }

  /// Discard the short-lived snapshot after an in-app tracker mutation. The
  /// API can retain an old playback row after that episode enters watched
  /// history, so consumers must rebuild the merge instead of serving it for
  /// another thirty seconds.
  void invalidate() {
    _cacheGeneration++;
    _lastGood = null;
    _lastFetchedAt = null;
  }

  Future<MdblistResult<MdblistContinueWatchingSnapshot>> fetch({
    bool force = false,
  }) async {
    if (!force &&
        _lastGood != null &&
        _lastFetchedAt != null &&
        DateTime.now().difference(_lastFetchedAt!) <
            const Duration(seconds: 30)) {
      debugPrint(
        '[MDBListDiag] CW cache hit movies=${_lastGood!.movies.length} '
        'shows=${_lastGood!.shows.length}',
      );
      return MdblistResult.success(_lastGood!);
    }
    final cacheGeneration = _cacheGeneration;
    final results = await Future.wait([
      service.fetchPlaybackSessions(),
      service.fetchUpNext(),
      service.fetchSyncSnapshot('watched', mediaType: 'episode'),
    ]);
    final playback = results[0] as MdblistResult<List<MdblistPlaybackSession>>;
    final upNext = results[1] as MdblistResult<List<Map<String, dynamic>>>;
    final watched = results[2] as MdblistResult<List<Map<String, dynamic>>>;
    debugPrint(
      '[MDBListDiag] CW API playbackKind=${playback.kind.name} '
      'playbackStatus=${playback.statusCode} '
      'playbackCount=${playback.data?.length ?? 0} '
      'upNextKind=${upNext.kind.name} upNextStatus=${upNext.statusCode} '
      'upNextCount=${upNext.data?.length ?? 0} '
      'watchedKind=${watched.kind.name} watchedCount=${watched.data?.length ?? 0}',
    );
    // Playback rows are not authoritative on their own: MDBList can retain a
    // paused row after the episode is already present in watched history. A
    // failed or truncated watched snapshot must therefore retain the previous
    // complete merge instead of resurrecting that completed episode.
    if (!playback.isSuccess || !upNext.isSuccess || !watched.isComplete) {
      final previous = _lastGood;
      if (previous != null) {
        return MdblistResult.partial(previous);
      }
      final failureKind = !playback.isSuccess
          ? playback.kind
          : !upNext.isSuccess
          ? upNext.kind
          : watched.kind == MdblistResultKind.partial
          ? MdblistResultKind.transientFailure
          : watched.kind;
      return MdblistResult.failure(
        failureKind,
        statusCode: !playback.isSuccess
            ? playback.statusCode
            : !upNext.isSuccess
            ? upNext.statusCode
            : watched.statusCode,
        retryAfter: !playback.isSuccess
            ? playback.retryAfter
            : !upNext.isSuccess
            ? upNext.retryAfter
            : watched.retryAfter,
      );
    }

    final moviesByImdb = <String, MdblistContinueWatchingItem>{};
    final showsByImdb = <String, MdblistContinueWatchingItem>{};
    final watchedEpisodes = <String>{};
    final watchedAtByEpisode = <String, DateTime?>{};
    for (final row in watched.data!) {
      final episode = _map(row['episode']) ?? row;
      final show = _map(episode['show']) ?? _map(row['show']);
      final ids = _map(show?['ids']);
      final imdb = _string(ids?['imdb'] ?? show?['imdb_id']);
      final season = _integer(episode['season'] ?? episode['season_number']);
      final number = _integer(episode['number'] ?? episode['episode_number']);
      if (imdb != null && season != null && number != null) {
        final key = _episodeKey(imdb, season, number);
        watchedEpisodes.add(key);
        watchedAtByEpisode[key] = mdblistDateTime(
          row['last_watched_at'] ?? episode['last_watched_at'],
        );
      }
    }
    void keepNewest(
      Map<String, MdblistContinueWatchingItem> target,
      MdblistContinueWatchingItem item,
    ) {
      final key = item.selection.imdbId.toLowerCase();
      final current = target[key];
      final currentAt =
          current?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final nextAt = item.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (current == null || nextAt.isAfter(currentAt)) target[key] = item;
    }

    final completedPlayback = <MdblistPlaybackSession>[];
    for (final session in playback.data!) {
      if (!session.isResumable) continue;
      if (session.isEpisode &&
          session.imdbId != null &&
          session.season != null &&
          session.episode != null &&
          watchedEpisodes.contains(
            _episodeKey(session.imdbId!, session.season!, session.episode!),
          )) {
        completedPlayback.add(session);
        continue;
      }
      final item = _fromPlayback(session);
      if (item == null) continue;
      if (session.isEpisode) {
        keepNewest(showsByImdb, item);
      } else {
        keepNewest(moviesByImdb, item);
      }
    }
    for (final row in upNext.data!) {
      final item = _fromUpNext(row);
      if (item == null) continue;
      showsByImdb.putIfAbsent(item.selection.imdbId.toLowerCase(), () => item);
    }
    // MDBList keeps a stale paused row after an episode is marked watched and
    // can simultaneously return no /upnext item. Do not drop the show: resolve
    // its MDBList season inventory and advance to the first unwatched aired
    // coordinate. Genuine playback and /upnext rows above always win.
    final advanced = await Future.wait([
      for (final session in completedPlayback)
        _advanceCompletedPlayback(session, watchedEpisodes, watchedAtByEpisode),
    ]);
    for (final item in advanced.nonNulls) {
      showsByImdb.putIfAbsent(item.selection.imdbId.toLowerCase(), () => item);
    }
    int newestFirst(
      MdblistContinueWatchingItem a,
      MdblistContinueWatchingItem b,
    ) => (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    final movies = moviesByImdb.values.toList()..sort(newestFirst);
    final shows = showsByImdb.values.toList()..sort(newestFirst);
    final snapshot = MdblistContinueWatchingSnapshot(
      movies: movies,
      shows: shows,
    );
    debugPrint(
      '[MDBListDiag] CW snapshot movies=${movies.length} '
      'shows=${shows.length} resumablePlayback='
      '${playback.data!.where((session) => session.isResumable).length}',
    );
    // A scrobble may have completed while these three reads were in flight.
    // Return the result to its original caller, but never let that pre-mutation
    // snapshot become the cache served to subsequent refreshes.
    if (cacheGeneration == _cacheGeneration) {
      _lastGood = snapshot;
      _lastFetchedAt = DateTime.now();
    }
    return MdblistResult.success(snapshot);
  }

  MdblistContinueWatchingItem? _fromPlayback(MdblistPlaybackSession session) {
    final imdb = session.imdbId;
    if (imdb == null || !imdb.startsWith('tt')) return null;
    if (session.isEpisode &&
        (session.season == null || session.episode == null)) {
      return null;
    }
    final container = session.isEpisode
        ? _map(session.raw['show'])
        : _map(session.raw['movie']);
    final title = _string(container?['title'] ?? container?['name']) ?? imdb;
    final poster = _poster(container, imdb);
    final type = session.isEpisode ? 'series' : 'movie';
    final ids = MdblistMediaIds(imdb: imdb);
    final clearTarget = session.isEpisode
        ? MdblistScrobbleTarget.episode(
            ids,
            season: session.season!,
            episode: session.episode!,
          )
        : MdblistScrobbleTarget.movie(ids);
    return MdblistContinueWatchingItem(
      selection: AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: session.isEpisode,
        title: title,
        year: _string(container?['year'] ?? container?['release_year']),
        season: session.season,
        episode: session.episode,
        contentType: type,
        posterUrl: poster,
        mdblistProgressPercent: session.progress,
        mdblistSource: true,
      ),
      playbackId: session.id < 0 ? null : session.id,
      paused: true,
      updatedAt: session.pausedAt ?? session.updatedAt,
      clearTarget: clearTarget,
    );
  }

  MdblistContinueWatchingItem? _fromUpNext(Map<String, dynamic> row) {
    final show = _map(row['show']) ?? row;
    final episode = _map(row['next_episode']) ?? _map(row['episode']);
    final ids = _map(show['ids']);
    final imdb = _string(ids?['imdb'] ?? show['imdb_id']);
    final season = _integer(
      episode?['season'] ?? episode?['season_number'] ?? row['season'],
    );
    final number = _integer(
      episode?['number'] ?? episode?['episode'] ?? row['episode_number'],
    );
    if (imdb == null ||
        !imdb.startsWith('tt') ||
        season == null ||
        number == null) {
      return null;
    }
    return MdblistContinueWatchingItem(
      selection: AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: _string(show['title'] ?? show['name']) ?? imdb,
        year: _string(show['year'] ?? show['release_year']),
        season: season,
        episode: number,
        contentType: 'series',
        posterUrl: _poster(show, imdb),
        mdblistSource: true,
      ),
      paused: false,
      updatedAt: mdblistDateTime(row['last_watched_at']),
    );
  }

  Future<MdblistContinueWatchingItem?> _advanceCompletedPlayback(
    MdblistPlaybackSession session,
    Set<String> watchedEpisodes,
    Map<String, DateTime?> watchedAtByEpisode,
  ) async {
    final imdb = session.imdbId;
    final currentSeason = session.season;
    final currentEpisode = session.episode;
    if (imdb == null || currentSeason == null || currentEpisode == null) {
      return null;
    }
    final metadata = await service.resolveImdb(imdb, 'series');
    if (!metadata.isSuccess) return null;
    final rawSeasons = metadata.data?['seasons'];
    if (rawSeasons is! List) return null;
    final seasons = <({int number, int episodes})>[];
    for (final raw in rawSeasons.whereType<Map<String, dynamic>>()) {
      final number = _integer(raw['season_number']);
      final count = _integer(
        raw['aired_episode_count'] ?? raw['episode_count'],
      );
      if (number != null && number > 0 && count != null && count > 0) {
        seasons.add((number: number, episodes: count));
      }
    }
    seasons.sort((a, b) => a.number.compareTo(b.number));

    ({int season, int episode})? next;
    for (final season in seasons) {
      if (season.number < currentSeason) continue;
      final start = season.number == currentSeason ? currentEpisode + 1 : 1;
      for (var episode = start; episode <= season.episodes; episode++) {
        if (!watchedEpisodes.contains(
          _episodeKey(imdb, season.number, episode),
        )) {
          next = (season: season.number, episode: episode);
          break;
        }
      }
      if (next != null) break;
    }
    if (next == null) return null;

    final show = _map(session.raw['show']);
    return MdblistContinueWatchingItem(
      selection: AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: _string(show?['title'] ?? show?['name']) ?? imdb,
        year: _string(show?['year'] ?? show?['release_year']),
        season: next.season,
        episode: next.episode,
        contentType: 'series',
        posterUrl: _poster(show, imdb),
        mdblistSource: true,
      ),
      paused: false,
      updatedAt:
          watchedAtByEpisode[_episodeKey(
            imdb,
            currentSeason,
            currentEpisode,
          )] ??
          session.pausedAt ??
          session.updatedAt,
    );
  }

  Future<bool> clear(MdblistContinueWatchingItem item) async {
    final target = item.clearTarget;
    if (!item.paused || target == null) return false;
    final response = await service.scrobbleClear(target);
    if (response.isSuccess) {
      invalidate();
      return true;
    }
    return false;
  }

  Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;
  String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _integer(Object? value) => value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value)
      : null;
  String _episodeKey(String imdb, int season, int episode) =>
      '${imdb.toLowerCase()}-$season-$episode';
  String _poster(Map<String, dynamic>? value, String imdb) =>
      _string(value?['poster'] ?? value?['poster_url']) ??
      'https://images.metahub.space/poster/medium/$imdb/img';
}
