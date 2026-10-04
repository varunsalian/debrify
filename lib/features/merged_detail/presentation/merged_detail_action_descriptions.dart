import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

class MergedDetailActionDescriptions {
  /// Human-readable description of each quick action, shown in the More menu.
  static String descriptionFor(TraktItemMenuAction a) {
    switch (a) {
      case TraktItemMenuAction.selectSource:
        return 'Pin a specific torrent or file as this title\'s source so every '
            'play uses it — no re-searching each time. Change or clear it here.';
      case TraktItemMenuAction.addToStremioTv:
        return 'Add this to your Stremio TV channel so it plays in your '
            'always-on rotation alongside your other picks.';
      case TraktItemMenuAction.playRandomEpisode:
        return 'Skip the browsing and jump straight into a random episode from '
            'this series — handy for background or comfort watching.';
      case TraktItemMenuAction.searchPacks:
        return 'Open a search for full-season and complete-series packs, then '
            'do whatever you want with a result — play it, download it, and more.';
      case TraktItemMenuAction.addToWatchlist:
        return 'Save this to your Trakt watchlist so you can find it later, '
            'synced across every device signed into your account.';
      case TraktItemMenuAction.removeFromWatchlist:
        return 'Take this off your Trakt watchlist — it won\'t appear in your '
            '"to watch" list anymore.';
      case TraktItemMenuAction.addToCollection:
        return 'Mark this as part of your Trakt collection — your library of '
            'everything you own or keep track of.';
      case TraktItemMenuAction.removeFromCollection:
        return 'Remove this from your Trakt collection.';
      case TraktItemMenuAction.markWatched:
        return 'Mark every episode of this title as watched on Trakt and sync '
            'that history across all your devices.';
      case TraktItemMenuAction.markUnwatched:
        return 'Clear this title from your Trakt history so it counts as '
            'unwatched again and can resurface in "up next".';
      case TraktItemMenuAction.rate:
        return 'Give this a 1–10 rating on Trakt. Your ratings sync everywhere '
            'and help shape your recommendations.';
      case TraktItemMenuAction.removeRating:
        return 'Remove the rating you previously gave this on Trakt.';
      case TraktItemMenuAction.addToList:
        return 'Add this to one of your custom Trakt lists — like "Weekend", '
            '"With friends" or anything you\'ve made.';
      case TraktItemMenuAction.removeFromList:
        return 'Remove this from one of your custom Trakt lists.';
      case TraktItemMenuAction.removeFromPlayback:
        return 'Remove this from Continue Watching so it stops showing on your '
            'home rows and resume list.';
      case TraktItemMenuAction.clearWatchProgress:
        return 'Reset watched history and resume progress on this device and connected Trakt, Simkl and MDBList accounts. Saved sources are kept.';
      case TraktItemMenuAction.clearTraktProgress:
        return 'Clear watched history and resume progress on Trakt only. Local progress and other trackers are kept.';
      case TraktItemMenuAction.removeFromTraktPlayback:
        return 'Delete this title\'s playback progress (and watch history) on '
            'Trakt so it leaves the Trakt Continue Watching rows.';
    }
  }
}
