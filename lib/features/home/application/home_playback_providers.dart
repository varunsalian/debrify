import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/episode_tracker_snapshot_revision.dart';
import '../../../services/local_series_completion_service.dart';
import '../../../services/mdblist/mdblist_continue_watching_service.dart';
import '../../../services/native_series_metadata_service.dart';
import '../../../services/next_episode_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/trakt/trakt_continue_watching_service.dart';
import '../data/home_catalog_playback_readers.dart';
import '../data/home_catalog_playback_resolver.dart';
import '../data/home_random_episode_selector.dart';
import '../data/home_random_playback_repository.dart';
import '../data/home_series_resume_repository.dart';
import '../data/home_series_resume_resolver.dart';
import '../data/home_tracker_resume_repository.dart';
import '../models/home_catalog_session.dart';
import 'home_detail_providers.dart';

final homeCatalogPlaybackResolverProvider = Provider.autoDispose
    .family<HomeCatalogPlaybackResolver, HomeCatalogSession>(
      (ref, session) {
        return HomeCatalogPlaybackResolver(
          seriesResume: ref.watch(homeSeriesResumeResolverProvider(session)),
          signals: ref.watch(homeSeriesResumeRepositoryProvider(session.owner)),
          trackers: ref.watch(homeTrackerResumeRepositoryProvider(session)),
          readers: HomeCatalogPlaybackReaders(session.owner),
          log: debugPrint,
        );
      },
      dependencies: [
        homeSeriesResumeResolverProvider,
        homeSeriesResumeRepositoryProvider,
        homeTrackerResumeRepositoryProvider,
      ],
    );

/// Stateless selection uses the same identity rules as ordinary playback.
final homeRandomEpisodeSelectorProvider = Provider<HomeRandomEpisodeSelector>(
  (ref) => const HomeRandomEpisodeSelector(
    videoIdFor: StremioService.randomEpisodeVideoId,
    isCanonicalEpisode: StremioService.isCanonicalEpisodeId,
  ),
  dependencies: const [],
);

/// The factory is disposable; an explicit operation retains its stateless
/// repository and captured scope. Its caller/owner guard determines retirement.
final homeRandomPlaybackRepositoryProvider = Provider.autoDispose
    .family<HomeRandomPlaybackRepository, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() read) {
          final scope = owner.scope;
          return scope == null
              ? read()
              : ProfileRuntime.withCapturedScope(scope, read);
        }

        bool current() => owner == ProfileSessionMemory.captureOwner();
        return HomeRandomPlaybackRepository(
          nativeAddon: NativeSeriesMetadataService.addon,
          selector: ref.watch(homeRandomEpisodeSelectorProvider),
          isOwnerCurrent: current,
          readAddons: () => scoped(StremioService.instance.getEnabledAddons),
          fetchEpisodes: (addon, contentId) => scoped(
            () => StremioService.instance.fetchSeriesMeta(addon, contentId),
          ),
          recordInventory: (id, title, videos, canCommit) => scoped(
            () =>
                LocalSeriesCompletionService.instance.recordRawEpisodeInventory(
                  imdbId: id,
                  seriesTitle: title,
                  videos: videos,
                  canCommit: () => current() && canCommit(),
                ),
          ),
          onInventoryError: (error, stack) => debugPrint(
            'Random playback inventory could not be recorded (${error.runtimeType})',
          ),
        );
      },
      retry: (count, error) => null,
      dependencies: [homeRandomEpisodeSelectorProvider],
    );

/// Stateless adapters may outlive provider disposal for an accepted call.
/// Captured profile ownership and the originating view guard govern acceptance;
/// services retain ownership of their own caches, credentials and native work.
final homeSeriesResumeRepositoryProvider = Provider.autoDispose
    .family<HomeSeriesResumeRepository, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeSeriesResumeRepository(
          selectTraktItem: (item, current) => scoped(
            () => TraktContinueWatchingService.instance.selectionForItem(
              item,
              canContinue: current,
            ),
          ),
          readTraktShows: (current) => scoped(
            () => TraktContinueWatchingService.instance.fetchItems(
              TraktContinueWatchingService.showsContentType,
              canContinue: current,
            ),
          ),
          resolveTraktShow: (id, current) => scoped(
            () => TraktContinueWatchingService.instance.resolveSelection(
              traktContentType: TraktContinueWatchingService.showsContentType,
              itemId: id,
              canContinue: current,
            ),
          ),
          readSimklPaused: (id, current) => scoped(
            () => SimklService.instance.fetchShowPlaybackSelection(
              id,
              canContinue: current,
            ),
          ),
          readSimklNext: (id, current) => scoped(
            () => SimklService.instance.fetchNextToWatch(
              id,
              canContinue: current,
            ),
          ),
          readLocalById: (id) =>
              scoped(() => StorageService.getLastPlayedEpisodeByImdbId(id)),
          readLocalByTitle: (title) => scoped(
            () => StorageService.getLastPlayedEpisode(seriesTitle: title),
          ),
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          log: debugPrint,
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeSeriesResumeResolverProvider = Provider.autoDispose
    .family<HomeSeriesResumeResolver, HomeCatalogSession>(
      (ref, session) {
        final resolver = HomeSeriesResumeResolver(
          signals: ref.watch(homeSeriesResumeRepositoryProvider(session.owner)),
          trackers: ref.watch(homeTrackerResumeRepositoryProvider(session)),
          policies: ref.watch(
            homeTrackingPolicyRepositoryProvider(session.owner),
          ),
          findNextEpisode:
              (id, season, episode, {required preferBuiltIn, catalogItem}) {
                Future<({int season, int episode})?> read() =>
                    NextEpisodeService.findNextEpisode(
                      id,
                      season,
                      episode,
                      preferBuiltIn: preferBuiltIn,
                      catalogItem: catalogItem,
                    );
                final scope = session.owner.scope;
                return scope == null
                    ? read()
                    : ProfileRuntime.withCapturedScope(scope, read);
              },
          readRevision: EpisodeTrackerSnapshotRevision.identity,
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
          now: DateTime.now,
          log: debugPrint,
        );
        ref.onDispose(resolver.dispose);
        return resolver;
      },
      retry: (count, error) => null,
      dependencies: [
        homeSeriesResumeRepositoryProvider,
        homeTrackerResumeRepositoryProvider,
        homeTrackingPolicyRepositoryProvider,
      ],
    );

final homeTrackerResumeRepositoryProvider = Provider.autoDispose
    .family<HomeTrackerResumeRepository, HomeCatalogSession>(
      (ref, session) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = session.owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        final repository = HomeTrackerResumeRepository(
          readTraktMovie: (id) => scoped(() async {
            final selection = await TraktContinueWatchingService.instance
                .resolveSelection(
                  traktContentType:
                      TraktContinueWatchingService.moviesContentType,
                  itemId: id,
                );
            return selection?.traktProgressPercent;
          }),
          readSimklMovie: (id) => scoped(
            () => SimklService.instance.fetchMoviePlaybackProgress(id),
          ),
          readMdblist: () =>
              scoped(() => MdblistContinueWatchingService.instance.fetch()),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
          now: DateTime.now,
        );
        ref.onDispose(repository.dispose);
        return repository;
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
