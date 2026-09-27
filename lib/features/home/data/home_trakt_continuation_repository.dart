import '../../../models/trakt_continue_watching_item.dart';
import '../models/home_trakt_continuation_read.dart';

/// Borrows existing authentication/feed services without adding cache or retry.
class HomeTraktContinuationRepository {
  const HomeTraktContinuationRepository({
    required Future<bool> Function() isAuthenticated,
    required Future<List<TraktContinueWatchingItem>?> Function() readMovies,
    required Future<List<TraktContinueWatchingItem>?> Function() readShows,
  }) : _isAuthenticated = isAuthenticated,
       _readMovies = readMovies,
       _readShows = readShows;

  final Future<bool> Function() _isAuthenticated;
  final Future<List<TraktContinueWatchingItem>?> Function() _readMovies;
  final Future<List<TraktContinueWatchingItem>?> Function() _readShows;

  /// Null means the owner retired; a null feed remains a failed refresh.
  Future<HomeTraktContinuationRead?> read({
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final authenticated = await _isAuthenticated();
    if (!isCurrent()) return null;
    if (!authenticated) {
      return const HomeTraktContinuationRead.disconnected();
    }
    final rows = await Future.wait([_readMovies(), _readShows()]);
    if (!isCurrent()) return null;
    final movies = rows[0];
    final shows = rows[1];
    if (movies == null || shows == null) {
      throw StateError('Trakt Continue Watching read failed');
    }
    return HomeTraktContinuationRead.connected(movies: movies, shows: shows);
  }
}
