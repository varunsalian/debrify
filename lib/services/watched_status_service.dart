import 'dart:async';

import 'package:flutter/foundation.dart';

import 'simkl/simkl_service.dart';
import 'local_series_completion_service.dart';
import 'storage_service.dart';
import 'trakt/trakt_service.dart';
import 'mdblist/mdblist_service.dart';

/// One asynchronous, account-wide watched snapshot for every poster card.
///
/// Pages never await this service. It publishes local movie completion first,
/// then folds in the two tracker bulk responses as they arrive. All card
/// lookups after that are O(1) set membership checks.
class WatchedStatusService extends ChangeNotifier {
  WatchedStatusService._() {
    StorageService.movieFinishedRevision.addListener(refresh);
    StorageService.localCompletionRevision.addListener(_refreshLocal);
    MdblistService.instance.watchedRevision.addListener(_markMdblistDirty);
  }

  static final WatchedStatusService instance = WatchedStatusService._();

  Set<String> _localMovies = const {};
  Set<String> _localSeries = const {};
  Set<String> _traktMovies = const {};
  Set<String> _traktSeries = const {};
  Set<String> _simklMovies = const {};
  Set<String> _simklSeries = const {};
  Set<String> _mdblistMovies = const {};
  Set<String> _mdblistSeries = const {};
  int _generation = 0;
  bool _started = false;
  bool _refreshing = false;
  bool _refreshPending = false;
  int _localGeneration = 0;
  bool _mdblistDirty = false;
  DateTime? _mdblistDirtyAt;
  Timer? _mdblistRefreshTimer;

  bool isWatched(String imdbId, String contentType) {
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty) return false;
    if (contentType.toLowerCase() == 'series') {
      return _localSeries.contains(id) ||
          _traktSeries.contains(id) ||
          _simklSeries.contains(id) ||
          _mdblistSeries.contains(id);
    }
    return _localMovies.contains(id) ||
        _traktMovies.contains(id) ||
        _simklMovies.contains(id) ||
        _mdblistMovies.contains(id);
  }

  /// Starts loading without returning work for the UI to await.
  void ensureStarted() {
    if (!_started) {
      _started = true;
      refresh();
      return;
    }
    // MDBList scrobble completion happens while Home is normally covered by
    // the player route. Defer the quota-sensitive account snapshot until an
    // active poster asks again instead of fetching every tracker immediately
    // after every episode.
    if (_mdblistDirty && !_refreshing) {
      _consumeMdblistDirty();
    }
  }

  void _markMdblistDirty() {
    _mdblistDirty = true;
    _mdblistDirtyAt = DateTime.now();
    _mdblistRefreshTimer?.cancel();
    _mdblistRefreshTimer = null;
  }

  void _consumeMdblistDirty() {
    if (!_mdblistDirty) return;
    // MDBList updates aggregate show completion shortly after accepting an
    // episode stop. Waiting here avoids consuming quota on a snapshot that is
    // guaranteed to be stale and then having no later invalidation to retry.
    const settleTime = Duration(seconds: 3);
    final dirtyAt = _mdblistDirtyAt;
    final elapsed = dirtyAt == null
        ? settleTime
        : DateTime.now().difference(dirtyAt);
    final remaining = settleTime - elapsed;
    if (remaining > Duration.zero) {
      _mdblistRefreshTimer ??= Timer(remaining, () {
        _mdblistRefreshTimer = null;
        if (!_mdblistDirty) return;
        _mdblistDirty = false;
        _mdblistDirtyAt = null;
        refresh();
      });
      return;
    }
    _mdblistDirty = false;
    _mdblistDirtyAt = null;
    refresh();
  }

  void refresh() {
    _generation++;
    if (_refreshing) {
      // Invalidate the in-flight result, then collapse any number of rapid
      // mutations into exactly one fresh pass after it exits.
      _refreshPending = true;
      return;
    }
    _startRefresh();
  }

  void _refreshLocal() {
    final generation = ++_localGeneration;
    unawaited(() async {
      final results = await Future.wait([
        StorageService.getFinishedMovieIds(),
        LocalSeriesCompletionService.instance.caughtUpIds(),
      ]);
      if (generation != _localGeneration) return;
      _localMovies = results[0];
      _localSeries = results[1];
      notifyListeners();

      // Calendar reconciliation may involve network requests. Keep it behind
      // the immediate local snapshot so card rendering never waits on Simkl.
      final calendarSeries = await LocalSeriesCompletionService.instance
          .refreshCalendarIfDue();
      if (generation != _localGeneration ||
          setEquals(_localSeries, calendarSeries)) {
        return;
      }
      _localSeries = calendarSeries;
      notifyListeners();
    }());
  }

  void _startRefresh() {
    _refreshing = true;
    final generation = _generation;
    unawaited(
      _refresh(generation).whenComplete(() {
        _refreshing = false;
        if (_refreshPending) {
          _refreshPending = false;
          _startRefresh();
        } else if (_mdblistDirty && _mdblistDirtyAt != null) {
          // A watched mutation can land while this pass is in flight. Badge
          // rebuilds happen before `_refreshing` is cleared, so hand the dirty
          // state off here rather than waiting for an unrelated future build.
          // API failures leave dirtyAt null and deliberately do not auto-loop.
          _consumeMdblistDirty();
        }
      }),
    );
  }

  Future<void> _refresh(int generation) async {
    final localGeneration = ++_localGeneration;
    final mdblistRevision = MdblistService.instance.watchedRevision.value;
    // Start network work immediately, but publish the cheap local snapshot as
    // soon as it resolves rather than waiting for either tracker.
    final traktFuture = _fetchTrakt();
    final simklFuture = SimklService.instance.fetchCompletedTitleIds();
    final mdblistFuture = MdblistService.instance.fetchCompletedTitleIds();
    final localSeriesFuture = LocalSeriesCompletionService.instance
        .caughtUpIds();
    final calendarFuture = LocalSeriesCompletionService.instance
        .refreshCalendarIfDue();

    final localMovies = await StorageService.getFinishedMovieIds();
    final localSeries = await localSeriesFuture;
    if (generation == _generation && localGeneration == _localGeneration) {
      _localMovies = localMovies;
      _localSeries = localSeries;
      notifyListeners();
    }

    // Always join the requests this pass started, even if invalidated. That
    // keeps the coalescer honest: the follow-up cannot overlap abandoned page
    // loops from the superseded pass.
    final results = await Future.wait<Object?>([
      traktFuture,
      simklFuture,
      calendarFuture,
      mdblistFuture,
    ]);
    if (generation != _generation) return;
    final trakt =
        results[0] as ({Map<String, double>? movies, Set<String>? series});
    final traktMovies = trakt.movies;
    final traktSeries = trakt.series;
    if (traktMovies != null) {
      _traktMovies = traktMovies.keys.map((id) => id.toLowerCase()).toSet();
    }
    if (traktSeries != null) _traktSeries = traktSeries;
    final simkl = results[1] as ({Set<String> movies, Set<String> series})?;
    if (simkl != null) {
      _simklMovies = simkl.movies;
      _simklSeries = simkl.series;
    }
    if (localGeneration == _localGeneration) {
      _localSeries = results[2] as Set<String>;
    }
    final mdblist = results[3] as ({Set<String> movies, Set<String> series})?;
    if (mdblist != null) {
      _mdblistMovies = mdblist.movies;
      _mdblistSeries = mdblist.series;
      if (MdblistService.instance.watchedRevision.value == mdblistRevision) {
        _mdblistDirty = false;
        _mdblistDirtyAt = null;
        _mdblistRefreshTimer?.cancel();
        _mdblistRefreshTimer = null;
      }
    } else {
      // A transient/rate-limit failure must retain the old truth and retry the
      // next time Home becomes active.
      _mdblistDirty = true;
    }
    notifyListeners();
  }

  Future<({Map<String, double>? movies, Set<String>? series})>
  _fetchTrakt() async {
    final trakt = TraktService.instance;
    if (!await trakt.isAuthenticated()) {
      return (movies: <String, double>{}, series: <String>{});
    }
    final results = await Future.wait<Object?>([
      trakt.fetchWatchedMoviesOrNull(),
      trakt.fetchFullyWatchedShowsOrNull(),
    ]);
    return (
      movies: results[0] as Map<String, double>?,
      series: results[1] as Set<String>?,
    );
  }
}
