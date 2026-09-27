import '../../../models/trakt_continue_watching_item.dart';

/// A disconnect clears shelves; a failed feed throws instead of becoming empty.
class HomeTraktContinuationRead {
  const HomeTraktContinuationRead.disconnected()
    : authenticated = false,
      movies = const [],
      shows = const [];

  HomeTraktContinuationRead.connected({
    required List<TraktContinueWatchingItem> movies,
    required List<TraktContinueWatchingItem> shows,
  }) : authenticated = true,
       movies = List.unmodifiable(movies),
       shows = List.unmodifiable(shows);

  final bool authenticated;
  final List<TraktContinueWatchingItem> movies;
  final List<TraktContinueWatchingItem> shows;
}
