import '../../../widgets/trakt/trakt_menu_helpers.dart'
    show TraktItemMenuAction;
import '../../../services/simkl/simkl_menu_helpers.dart'
    show SimklItemMenuAction;
import '../../../services/mdblist/mdblist_menu_helpers.dart'
    show MdblistItemMenuAction;

/// Detail actions borrow the view's existing handlers and row controllers.
/// This boundary owns dispatch/refresh ordering, not tracker transport or writes.
class HomeDetailActionBridge {
  const HomeDetailActionBridge({
    required this.isCurrent,
    required this.isSearch,
    required this.clearResume,
    required this.refreshLocal,
    required this.refreshTrakt,
    required this.refreshSimkl,
    required this.refreshMdblist,
  });

  final bool Function() isCurrent, isSearch;
  final void Function() clearResume;
  final Future<void> Function() refreshLocal,
      refreshTrakt,
      refreshSimkl,
      refreshMdblist;

  Future<void> trakt(
    TraktItemMenuAction action, {
    required Future<void> Function(bool clearOnly) invoke,
    required Future<void> Function() removeLocal,
    required Future<void> Function() removeTrakt,
  }) async {
    if (!isCurrent()) return;
    if (action == TraktItemMenuAction.removeFromPlayback) {
      await removeLocal();
      return;
    }
    if (action == TraktItemMenuAction.removeFromTraktPlayback) {
      await removeTrakt();
      return;
    }
    final clearOnly = action == TraktItemMenuAction.clearWatchProgress;
    await invoke(clearOnly);
    if (!isCurrent()) return;
    if (clearOnly) {
      clearResume();
      await Future.wait([
        refreshLocal(),
        refreshTrakt(),
        refreshSimkl(),
        refreshMdblist(),
      ]);
      return;
    }
    if (!isSearch() &&
        (action == TraktItemMenuAction.clearTraktProgress ||
            action == TraktItemMenuAction.markWatched ||
            action == TraktItemMenuAction.markUnwatched)) {
      await refreshTrakt();
    }
  }

  Future<void> simkl(
    SimklItemMenuAction action, {
    required Future<void> Function() invoke,
  }) async {
    if (!isCurrent()) return;
    await invoke();
    if (!isCurrent() || isSearch()) return;
    if (action == SimklItemMenuAction.clearWatchProgress ||
        action == SimklItemMenuAction.removeFromContinueWatching ||
        action == SimklItemMenuAction.removeFromList ||
        action == SimklItemMenuAction.moveToCompleted ||
        action == SimklItemMenuAction.moveToDropped ||
        action == SimklItemMenuAction.moveToOnHold ||
        action == SimklItemMenuAction.moveToWatching) {
      await refreshSimkl();
    }
  }

  Future<void> mdblist(
    MdblistItemMenuAction action, {
    required Future<void> Function() invoke,
    required Future<void> Function() remove,
  }) async {
    if (!isCurrent()) return;
    if (action == MdblistItemMenuAction.removeFromContinueWatching) {
      await remove();
      return;
    }
    await invoke();
    if (!isCurrent() || isSearch()) return;
    if (action == MdblistItemMenuAction.clearWatchProgress ||
        action == MdblistItemMenuAction.markWatched ||
        action == MdblistItemMenuAction.markUnwatched ||
        action == MdblistItemMenuAction.drop ||
        action == MdblistItemMenuAction.restore) {
      await refreshMdblist();
    }
  }
}
