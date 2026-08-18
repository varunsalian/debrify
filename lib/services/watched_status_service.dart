import 'dart:async';

import 'package:flutter/foundation.dart';

import 'simkl/simkl_service.dart';
import 'storage_service.dart';
import 'trakt/trakt_service.dart';

/// One asynchronous, account-wide watched snapshot for every poster card.
///
/// Pages never await this service. It publishes local movie completion first,
/// then folds in the two tracker bulk responses as they arrive. All card
/// lookups after that are O(1) set membership checks.
class WatchedStatusService extends ChangeNotifier {
  WatchedStatusService._() {
    StorageService.movieFinishedRevision.addListener(refresh);
  }

  static final WatchedStatusService instance = WatchedStatusService._();

  Set<String> _localMovies = const {};
  Set<String> _traktMovies = const {};
  Set<String> _traktSeries = const {};
  Set<String> _simklMovies = const {};
  Set<String> _simklSeries = const {};
  int _generation = 0;
  bool _started = false;
  bool _refreshing = false;
  bool _refreshPending = false;

  bool isWatched(String imdbId, String contentType) {
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty) return false;
    if (contentType.toLowerCase() == 'series') {
      return _traktSeries.contains(id) || _simklSeries.contains(id);
    }
    return _localMovies.contains(id) ||
        _traktMovies.contains(id) ||
        _simklMovies.contains(id);
  }

  /// Starts loading without returning work for the UI to await.
  void ensureStarted() {
    if (_started) return;
    _started = true;
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

  void _startRefresh() {
    _refreshing = true;
    final generation = _generation;
    unawaited(
      _refresh(generation).whenComplete(() {
        _refreshing = false;
        if (_refreshPending) {
          _refreshPending = false;
          _startRefresh();
        }
      }),
    );
  }

  Future<void> _refresh(int generation) async {
    // Start network work immediately, but publish the cheap local snapshot as
    // soon as it resolves rather than waiting for either tracker.
    final traktFuture = _fetchTrakt();
    final simklFuture = SimklService.instance.fetchCompletedTitleIds();

    final localMovies = await StorageService.getFinishedMovieIds();
    if (generation == _generation) {
      _localMovies = localMovies;
      notifyListeners();
    }

    // Always join the requests this pass started, even if invalidated. That
    // keeps the coalescer honest: the follow-up cannot overlap abandoned page
    // loops from the superseded pass.
    final results = await Future.wait<Object?>([traktFuture, simklFuture]);
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
