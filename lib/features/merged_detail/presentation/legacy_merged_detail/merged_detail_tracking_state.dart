import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

class MergedDetailTrackingState {
  /// The user's live Trakt relationship to this title (watchlist / collection /
  /// watched / rating). Null until [traktStatusLoader] resolves — the menu then
  /// falls back to the add-only [traktMenuOptions]. Re-read after a quick action
  /// and when the player pops back.
  TraktTitleStatus? traktStatus;

  /// Whether the status loaders have answered at least once. A null status
  /// means "untracked" only *after* this flips — before it, the answer simply
  /// isn't in yet, and the pill must not claim the title is untracked.
  bool traktStatusResolved = false;
  bool simklStatusResolved = false;
  bool mdblistStatusResolved = false;

  /// Debrify's own actions. They arrive inside the Trakt option list (that list
  /// has always carried both), but none of them touch Trakt — so they get the
  /// neutral "More" sheet and the Trakt sheet stays purely Trakt. Being app
  /// actions they're also available when Trakt is disconnected, which the old
  /// single-menu arrangement only managed by keeping an always-present Trakt
  /// button.
  static const Set<TraktItemMenuAction> appOwnedActions = {
    TraktItemMenuAction.selectSource,
    TraktItemMenuAction.addToStremioTv,
    TraktItemMenuAction.playRandomEpisode,
    TraktItemMenuAction.searchPacks,
    TraktItemMenuAction.removeFromPlayback,
    TraktItemMenuAction.clearWatchProgress,
  };

  /// The user's live Simkl relationship to this title. Null until
  /// [simklStatusLoader] resolves — mirrors [_traktStatus] one-for-one.
  SimklTitleStatus? simklStatus;
  MdblistTitleStatus? mdblistStatus;
  bool localMovieFinished = false;

  /// Debrify's local watchlist is independent of tracker connectivity.
  bool inMyWatchlist = false;

  int movieCompletionGeneration = 0;
}

const appOwnedActions = MergedDetailTrackingState.appOwnedActions;
