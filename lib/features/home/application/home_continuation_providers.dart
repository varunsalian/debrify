import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/episode_artwork_service.dart';
import '../../../services/iptv_cw_history.dart';
import '../../../services/local_history_removal.dart';
import '../../../services/mdblist/mdblist_continue_watching_service.dart';
import '../../../services/mdblist/mdblist_service.dart';
import '../../../services/mdblist/mdblist_sync_coordinator.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_continue_watching_removal.dart';
import '../../../services/simkl/simkl_continue_watching_service.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/trakt/trakt_continue_watching_service.dart';
import '../../../services/trakt/trakt_service.dart';
import '../data/home_continuation_layout_repository.dart';
import '../data/home_episode_artwork_repository.dart';
import '../data/home_iptv_history_removal.dart';
import '../data/home_local_continuation_repository.dart';
import '../data/home_mdblist_continuation_repository.dart';
import '../data/home_simkl_continuation_reader.dart';
import '../data/home_trakt_continuation_repository.dart';
import '../data/home_trakt_history_removal.dart';
import '../models/home_catalog_session.dart';
import '../models/home_tracker_authentication.dart';

final homeContinuationLayoutRepositoryProvider =
    Provider<HomeContinuationLayoutRepository>(
      (ref) => HomeContinuationLayoutRepository(
        readMerged: StorageService.getHomeCwMergedRows,
      ),
      dependencies: const [],
    );

final homeLocalContinuationRepositoryProvider =
    Provider<HomeLocalContinuationRepository>(
      (ref) => HomeLocalContinuationRepository(
        readProgressSource: StorageService.getWatchProgressSource,
        readEnabled: StorageService.getHomeContinueWatchingEnabled,
        readItems: StorageService.getContinueWatchingItems,
        readAddons: StremioService.instance.getEnabledAddons,
        readEpisode: StorageService.getLastPlayedEpisodeByImdbId,
        readMovie: StorageService.getVideoPlaybackStateByImdbId,
      ),
      dependencies: const [],
    );

final homeTraktContinuationRepositoryProvider =
    Provider<HomeTraktContinuationRepository>(
      (ref) => HomeTraktContinuationRepository(
        isAuthenticated: () => TraktService.instance.isAuthenticated(),
        readMovies: () =>
            TraktContinueWatchingService.instance.fetchMoviesOrNull(),
        readShows: () =>
            TraktContinueWatchingService.instance.fetchShowsOrNull(),
      ),
      dependencies: const [],
    );

final homeTraktHistoryRemovalProvider = Provider.autoDispose
    .family<HomeTraktHistoryRemoval, ProfileSessionOwner>(
      (ref, owner) => HomeTraktHistoryRemoval(owner),
      dependencies: const [],
    );

final homeSimklContinuationReaderProvider =
    Provider<HomeSimklContinuationReader>(
      (ref) =>
          () => SimklContinueWatchingService.instance.fetchItems(),
      dependencies: const [],
    );

final homeSimklHistoryRemovalProvider = Provider.autoDispose
    .family<SimklContinueWatchingRemoval, ProfileSessionOwner>(
      (ref, owner) => SimklContinueWatchingRemoval(owner),
      dependencies: const [],
    );

final homeMdblistContinuationRepositoryProvider =
    Provider<HomeMdblistContinuationRepository>(
      (ref) => HomeMdblistContinuationRepository(
        clear: (item) => MdblistContinueWatchingService.instance.clear(item),
        invalidate: () => MdblistContinueWatchingService.instance.invalidate(),
        synchronizeInvalidations: () =>
            MdblistSyncCoordinator.instance.synchronizeInvalidations(),
        fetch: ({required force}) =>
            MdblistContinueWatchingService.instance.fetch(force: force),
      ),
      dependencies: const [],
    );

final homeIptvContinuationRepositoryProvider = Provider<IptvCwHistory>(
  (ref) => IptvCwHistory(readHistory: StorageService.getIptvContinueWatching),
  dependencies: const [],
);

final homeIptvHistoryRemovalProvider = Provider.autoDispose
    .family<HomeIptvHistoryRemoval, ProfileSessionOwner>(
      (ref, owner) => HomeIptvHistoryRemoval(owner),
      dependencies: const [],
    );

final homeLocalHistoryRemovalProvider = Provider.autoDispose
    .family<LocalHistoryRemoval, ProfileSessionOwner>((ref, owner) {
      return LocalHistoryRemoval(
        isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
        write: (id) {
          final scope = owner.scope;
          Future<void> remove() async {
            await StorageService.removeContinueWatchingItem(id);
            await StorageService.clearPlaybackStateByImdbId(id);
          }

          return scope == null
              ? remove()
              : ProfileRuntime.withCapturedScope(scope, remove);
        },
      );
    }, dependencies: const []);

/// Preserve each service's authentication/refresh policy and originating scope.
final homeTrackerAuthReaderProvider = Provider.autoDispose
    .family<HomeTrackerAuthReader, HomeTrackerAuthSession>(
      (ref, session) => () async {
        if (session.view.owner != ProfileSessionMemory.captureOwner()) {
          return false;
        }
        Future<bool> read() => switch (session.tracker) {
          HomeTracker.trakt => TraktService.instance.isAuthenticated(),
          HomeTracker.simkl => SimklService.instance.isAuthenticated(),
          HomeTracker.mdblist => MdblistService.instance.isAuthenticated(),
        };
        final scope = session.view.owner.scope;
        return scope == null
            ? read()
            : ProfileRuntime.withCapturedScope(scope, read);
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeEpisodeArtworkRepositoryProvider = Provider.autoDispose
    .family<HomeEpisodeArtworkRepository, HomeCatalogSession>(
      (ref, session) => HomeEpisodeArtworkRepository(({
        required imdbId,
        required season,
        required episode,
      }) async {
        if (session.owner != ProfileSessionMemory.captureOwner()) return null;
        Future<String?> read() => EpisodeArtworkService.instance.resolve(
          imdbId: imdbId,
          season: season,
          episode: episode,
        );
        final scope = session.owner.scope;
        return scope == null
            ? read()
            : ProfileRuntime.withCapturedScope(scope, read);
      }),
      retry: (count, error) => null,
      dependencies: const [],
    );
