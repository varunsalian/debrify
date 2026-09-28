import '../models/tracking_source.dart';
import 'mdblist/mdblist_models.dart';
import 'mdblist/mdblist_service.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_session_memory.dart';
import 'series_progress_reset_service.dart';
import 'simkl/simkl_service.dart';
import 'tracker_title_actions.dart';
import 'trakt/trakt_service.dart';
import 'watched_action_coordinator.dart';
import 'watched_status_service.dart';

/// Borrows existing tracker services; never owns their caches or credentials.
/// The caller owns dialogs and navigation. Accepted writes retain this scope.
class ProfileTrackerTitleActions implements TrackerTitleActions {
  const ProfileTrackerTitleActions(this.owner);

  final ProfileSessionOwner owner;

  bool _current(bool Function() isCurrent) =>
      owner == ProfileSessionMemory.captureOwner() && isCurrent();

  Future<T> _scoped<T>(Future<T> Function() action) {
    final scope = owner.scope;
    return scope == null
        ? action()
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  @override
  Future<bool> mutate(
    TrackingSource tracker,
    TrackerTitleMutation mutation,
    String id,
    String type, {
    int? rating,
    String? listId,
    required bool Function() isCurrent,
  }) async {
    bool current() => _current(isCurrent);
    if (!current()) return false;
    final result = await _scoped<bool>(() async {
      if (mutation == TrackerTitleMutation.markWatched ||
          mutation == TrackerTitleMutation.markUnwatched) {
        // Branded actions force that tracker even when scrobbling is disabled.
        final result = await WatchedActionCoordinator.setTitleWatched(
          imdbId: id,
          contentType: type,
          watched: mutation == TrackerTitleMutation.markWatched,
          forceTargets: {tracker},
          canContinue: current,
        );
        if (result.success && tracker == TrackingSource.mdblist && current()) {
          WatchedStatusService.instance.ensureStarted();
        }
        return result.success;
      }
      switch (tracker) {
        case TrackingSource.trakt:
          final service = TraktService.instance;
          return switch (mutation) {
            TrackerTitleMutation.addToWatchlist => service.addToWatchlist(
              id,
              type,
              canContinue: current,
            ),
            TrackerTitleMutation.removeFromWatchlist =>
              service.removeFromWatchlist(id, type, canContinue: current),
            TrackerTitleMutation.addToCollection => service.addToCollection(
              id,
              type,
              canContinue: current,
            ),
            TrackerTitleMutation.removeFromCollection =>
              service.removeFromCollection(id, type, canContinue: current),
            TrackerTitleMutation.rate when rating != null => service.rateItem(
              id,
              type,
              rating,
              canContinue: current,
            ),
            TrackerTitleMutation.removeRating => service.removeRating(
              id,
              type,
              canContinue: current,
            ),
            TrackerTitleMutation.addToCustomList when listId != null =>
              service.addToCustomList(listId, id, type, canContinue: current),
            _ => false,
          };
        case TrackingSource.simkl:
          final service = SimklService.instance;
          switch (mutation) {
            case TrackerTitleMutation.addToWatchlist:
              return service.addToList(
                id,
                type,
                'plantowatch',
                canContinue: current,
              );
            case TrackerTitleMutation.moveToWatching:
              return service.addToList(
                id,
                type,
                'watching',
                canContinue: current,
              );
            case TrackerTitleMutation.moveToOnHold:
              return service.addToList(id, type, 'hold', canContinue: current);
            case TrackerTitleMutation.drop:
              if (!await service.addToList(
                    id,
                    type,
                    'dropped',
                    canContinue: current,
                  ) ||
                  !current()) {
                return false;
              }
              // The paused session is what keeps a dropped title in Continue Watching.
              return service.deletePlaybackForImdb(
                id,
                contentType: type,
                canContinue: current,
              );
            case TrackerTitleMutation.removeFromList:
              return service.removeFromListAndPlayback(
                id,
                type,
                canContinue: current,
              );
            case TrackerTitleMutation.rate:
              return rating == null
                  ? false
                  : service.rateItem(id, type, rating, canContinue: current);
            case TrackerTitleMutation.removeRating:
              return service.removeRating(id, type, canContinue: current);
            default:
              return false;
          }
        case TrackingSource.mdblist:
          final service = MdblistService.instance;
          final ids = MdblistMediaIds(imdb: id);
          final mediaType = type == 'series' ? 'show' : 'movie';
          return switch (mutation) {
            TrackerTitleMutation.addToWatchlist => service.addToWatchlist(
              ids,
              mediaType,
              canContinue: current,
            ),
            TrackerTitleMutation.removeFromWatchlist =>
              service.removeFromWatchlist(ids, mediaType, canContinue: current),
            TrackerTitleMutation.addToCollection => service.addToCollection(
              ids,
              mediaType,
              canContinue: current,
            ),
            TrackerTitleMutation.removeFromCollection =>
              service.removeFromCollection(
                ids,
                mediaType,
                canContinue: current,
              ),
            TrackerTitleMutation.rate when rating != null => service.rateTitle(
              ids,
              mediaType,
              rating,
              canContinue: current,
            ),
            TrackerTitleMutation.removeRating => service.removeRating(
              ids,
              mediaType,
              canContinue: current,
            ),
            TrackerTitleMutation.drop => service.setDropped(
              ids,
              dropped: true,
              canContinue: current,
            ),
            TrackerTitleMutation.restore => service.setDropped(
              ids,
              dropped: false,
              canContinue: current,
            ),
            _ => false,
          };
        default:
          return false;
      }
    });
    return current() && result;
  }

  @override
  Future<List<Map<String, dynamic>>> customLists({
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent)) return [];
    final lists = await _scoped(
      () => TraktService.instance.fetchCustomLists(
        canContinue: () => _current(isCurrent),
      ),
    );
    return _current(isCurrent) ? lists : [];
  }

  @override
  Future<List<String>> reset(
    String id,
    String title, {
    required bool isMovie,
    TrackingSource? provider,
    required bool Function() isCurrent,
  }) {
    if (!_current(isCurrent)) {
      return Future.value([
        switch (provider) {
          TrackingSource.trakt => 'Trakt',
          TrackingSource.simkl => 'Simkl',
          TrackingSource.mdblist => 'MDBList',
          _ => 'this device',
        },
      ]);
    }
    return _scoped(
      () => provider == null
          ? SeriesProgressResetService.clear(id, title, isMovie: isMovie)
          : SeriesProgressResetService.clearProvider(
              id,
              title,
              provider: provider,
              isMovie: isMovie,
            ),
    );
  }
}
