import 'package:debrify/services/simkl/simkl_menu_helpers.dart';

class MergedDetailSimklDescriptions {
  /// Human-readable description of each Simkl quick action, shown in its
  /// own More menu — mirrors [_descriptionFor].
  static String descriptionForSimkl(SimklItemMenuAction a) {
    switch (a) {
      case SimklItemMenuAction.clearWatchProgress:
        return 'Clear watched history and resume progress on Simkl only. Local progress and other trackers are kept.';
      case SimklItemMenuAction.moveToPlanToWatch:
        return 'Move this to your Simkl "Plan to Watch" list — a personal '
            'watch queue synced across every device signed into your account.';
      case SimklItemMenuAction.moveToWatching:
        return 'Mark this as currently watching on Simkl, without changing '
            'any episode watched state.';
      case SimklItemMenuAction.moveToOnHold:
        return 'Pause this on Simkl — keeps it out of Plan to Watch and '
            'Watching until you\'re ready to pick it back up.';
      case SimklItemMenuAction.moveToCompleted:
        return 'Mark this completed on Simkl and sync that history across '
            'all your devices.';
      case SimklItemMenuAction.moveToDropped:
        return 'Mark this dropped on Simkl so it stops showing up as '
            'something you\'re meaning to finish.';
      case SimklItemMenuAction.removeFromList:
        return 'Remove this title from your Simkl library, including its '
            'active status, watched history, rating and saved playback progress.';
      case SimklItemMenuAction.removeFromContinueWatching:
        return 'Take this off your Simkl Continue Watching rows. A movie just '
            'clears its paused position; a series is moved to On Hold so its '
            'next episode doesn\'t re-surface as an "up next" card.';
      case SimklItemMenuAction.rate:
        return 'Give this a 1–10 rating on Simkl.';
      case SimklItemMenuAction.removeRating:
        return 'Remove the rating you previously gave this on Simkl.';
    }
  }
}
