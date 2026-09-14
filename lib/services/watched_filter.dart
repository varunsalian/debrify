import '../models/stremio_addon.dart';
import 'hide_watched_prefs.dart';
import 'watched_status_service.dart';

/// Drops already-watched titles from catalog lists while the "Hide watched
/// titles" switch is on.
///
/// "Watched" is [WatchedStatusService]'s answer — the same tick-source-masked
/// union of local completion, Trakt, Simkl and MDBList that draws the ✓ on
/// posters — so the tick and the hiding never disagree. For shows it means
/// the whole show is finished, never "saw one episode".
///
/// Only movies and series with an IMDb id can be matched; everything else
/// passes. Nothing is hidden until the first watched snapshot has been
/// published, so a cold start paints the same list as before rather than
/// losing items a beat later.
class WatchedFilter {
  WatchedFilter._();

  /// True while the switch is on; callers can skip work entirely otherwise.
  static bool get enabled => HideWatchedPrefs.enabled;

  /// [hides] as a nullable predicate for `fetchFilteredPage`: null when the
  /// switch is off, which makes the pager a single plain fetch.
  static bool Function(StremioMeta)? get predicate => enabled ? hides : null;

  /// Whether [m] should be left out of a catalog surface.
  static bool hides(StremioMeta m) {
    if (!enabled) return false;
    final status = WatchedStatusService.instance;
    if (!status.hasSnapshot) {
      // Kick off the first refresh so the next load is filtered; this one
      // paints unfiltered rather than flashing.
      status.ensureStarted();
      return false;
    }
    if (!_matchable(m)) return false;
    return status.isWatchedForTicks(m.effectiveImdbId!, m.type);
  }

  /// [items] without the hidden ones. Returns [items] itself when the switch
  /// is off, so unfiltered callers pay nothing.
  static List<StremioMeta> apply(List<StremioMeta> items) {
    if (!enabled) return items;
    return [
      for (final m in items)
        if (!hides(m)) m,
    ];
  }

  static bool _matchable(StremioMeta m) {
    final type = m.type.toLowerCase();
    if (type != 'movie' && type != 'series') return false;
    final imdb = m.effectiveImdbId;
    return imdb != null && imdb.isNotEmpty;
  }
}
