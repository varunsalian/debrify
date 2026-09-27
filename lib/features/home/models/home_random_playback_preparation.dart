import '../../../models/advanced_search_selection.dart';

enum HomeRandomPlaybackStatus { ready, noEpisodes, loadFailed, retired }

/// Preparation emits data only; presentation owns messages and player handoff.
class HomeRandomPlaybackPreparation {
  const HomeRandomPlaybackPreparation.ready(AdvancedSearchSelection value)
    : status = HomeRandomPlaybackStatus.ready,
      selection = value;
  const HomeRandomPlaybackPreparation.noEpisodes()
    : status = HomeRandomPlaybackStatus.noEpisodes,
      selection = null;
  const HomeRandomPlaybackPreparation.loadFailed()
    : status = HomeRandomPlaybackStatus.loadFailed,
      selection = null;
  const HomeRandomPlaybackPreparation.retired()
    : status = HomeRandomPlaybackStatus.retired,
      selection = null;

  final HomeRandomPlaybackStatus status;
  final AdvancedSearchSelection? selection;
}
