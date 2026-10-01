import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stremio_addon.dart';
import '../../../widgets/trakt/trakt_menu_helpers.dart'
    show TraktItemMenuAction;
import '../application/home_continuation_providers.dart';
import '../models/home_catalog_session.dart';
import 'home_continuation_loading.dart';
import 'home_continuation_section.dart';
import 'home_detail_route.dart';
import 'home_playback_navigation.dart';

typedef HomeContinuationRemovalDeps = ({
  bool Function() mounted,
  bool Function() profileCurrent,
  HomeCatalogSession Function() session,
  String? Function(StremioMeta) imdbOf,
  Future<void> Function(StremioMeta) removeSimkl,
});

/// Continuation removals retain each provider's guards, route closing and refresh order.
class HomeContinuationRemoval {
  HomeContinuationRemoval(
    this._ref,
    this._deps,
    this._section,
    this._loading,
    this._playback,
  );
  final WidgetRef _ref;
  final HomeContinuationRemovalDeps _deps;
  final HomeContinuationSection _section;
  final HomeContinuationLoading _loading;
  final HomePlaybackNavigation _playback;

  Future<bool> removeLocalHistory(String id) async {
    if (!_playback.catalogNavigationCurrent()) return false;
    return _ref
        .read(homeLocalHistoryRemovalProvider(_deps.session().owner))
        .remove(id, isCurrent: _playback.catalogNavigationCurrent);
  }

  /// Detail-screen action for a Continue Watching title. Only handles removal;
  /// closes its own detail and lets the route return callback refresh the row.
  Future<void> handleContinueDetailAction(
    TraktItemMenuAction action,
    String imdbId,
    HomeDetailRoute detailRoute,
  ) async {
    if (!detailRoute.isActive ||
        action != TraktItemMenuAction.removeFromPlayback) {
      return;
    }
    if (!await removeLocalHistory(imdbId) ||
        !_deps.mounted() ||
        !detailRoute.isActive) {
      return;
    }
    detailRoute.closeIfCurrent();
    _playback.snack('Removed from Continue Watching');
  }

  /// Detail-screen action for a Trakt Continue Watching title: delete the
  /// title's playback entries (and watch history, so shows don't reappear via
  /// "Up Next") on Trakt, then pop the detail and reload the Trakt rows —
  /// mirroring the old home screen's remove flow.
  ///
  /// Row-menu removals have no detail route. Detail actions carry their exact
  /// route so a delayed response cannot pop a newer page. The route only
  /// admits the action and is closed if still current: users may back out
  /// while the Trakt calls finish, and those calls must still complete.
  Future<void> removeFromTraktContinueWatching(
    String imdbId, {
    HomeDetailRoute? detailRoute,
  }) async {
    final current = _playback.catalogNavigationCurrent;
    if (!current() || !(detailRoute?.isActive ?? true)) return;
    final cwItem = _section.traktByImdb[imdbId];
    if (cwItem == null) return;
    final removed = await _ref
        .read(homeTraktHistoryRemovalProvider(_deps.session().owner))
        .remove(cwItem, isCurrent: current);
    if (!_deps.mounted() || removed == null || !current()) return;
    if (!removed) {
      _playback.snack('Failed to remove from Trakt Continue Watching');
      return;
    }
    detailRoute?.closeIfCurrent();
    _playback.snack('Removed from Trakt Continue Watching');
    await _loading.loadTraktContinueWatching(refreshBound: false);
  }

  /// Remove a LOCAL Continue Watching title from the row itself. The same two
  /// writes [handleContinueDetailAction] makes (list entry + saved position),
  /// without the detail pop — nothing was pushed here.
  Future<void> removeLocalCwItem(StremioMeta item) async {
    final imdbId = _deps.imdbOf(item) ?? item.id;
    if (imdbId.isEmpty) return;
    if (!await removeLocalHistory(imdbId) || !_deps.mounted()) return;
    _playback.snack('Removed from Continue Watching');
    await _loading.loadContinueWatching();
  }

  /// Remove a Trakt Continue Watching title from the row itself — the detail
  /// page's flow minus the pop.
  Future<void> removeTraktCwItem(StremioMeta item) async {
    final imdbId = _deps.imdbOf(item);
    if (imdbId == null) return;
    await removeFromTraktContinueWatching(imdbId);
  }

  /// Remove a Simkl Continue Watching title from the row itself. Routes through
  /// the shared [handleSimklMenuAction] the detail sheet uses (which shows its
  /// own result snackbar), so a series is moved to On Hold and its paused
  /// session cleared, and a movie just loses the session.
  Future<void> removeSimklCwItem(StremioMeta item) async {
    if (!_playback.catalogNavigationCurrent()) return;
    await _deps.removeSimkl(item);
    if (!_playback.catalogNavigationCurrent()) return;
    await _loading.loadSimklContinueWatching(refreshBound: false);
  }

  /// Remove an IPTV Continue Watching card: a movie drops its own history +
  /// resume entry, a series drops every episode's (the card collapses them, so
  /// leaving one behind would just rebuild it).
  Future<void> removeIptvCwItem(StremioMeta item) async {
    if (!_playback.catalogNavigationCurrent()) return;
    final entry = _section.iptvCwByKey[item.id];
    if (entry == null) return;
    final removed = await _ref
        .read(homeIptvHistoryRemovalProvider(_deps.session().owner))
        .remove(entry, isCurrent: _playback.catalogNavigationCurrent);
    if (!removed) return;
    _playback.snack('Removed from Continue Watching');
    await _loading.loadIptvContinueWatching();
  }

  bool canRemoveMdblistCwItem(StremioMeta item) =>
      _section.mdblistByImdb[_deps.imdbOf(item)]?.paused == true;

  Future<void> removeMdblistCwItem(StremioMeta item) async {
    final removed = await _section.mdblistContinuationController.remove(
      _deps.imdbOf(item),
      isCurrent: _playback.catalogNavigationCurrent,
    );
    if (!_deps.mounted() || !removed || !_deps.profileCurrent()) {
      return;
    }
    _playback.snack('Removed from MDBList Continue Watching');
    await _loading.loadMdblistContinueWatching();
  }
}
