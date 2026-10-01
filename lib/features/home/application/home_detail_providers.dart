import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/mdblist/mdblist_service.dart';
import '../../../services/native_series_metadata_service.dart';
import '../../../services/profile_tracker_title_actions.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/tracker_title_actions.dart';
import '../../../services/tracking_source_policy.dart';
import '../../../services/trakt/trakt_service.dart';
import '../data/home_catalog_episode_identity.dart';
import '../data/home_catalog_origin_repository.dart';
import '../data/home_detail_readers.dart';
import '../data/home_source_editing_repository.dart';
import '../data/home_tracking_policy_repository.dart';

/// Stateless readers borrow existing services and keep the opening profile scope.
/// Disposal does not cancel service-owned caches or another route's shared reads.
final homeDetailReadersProvider = Provider.autoDispose
    .family<HomeDetailReaders, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeDetailReaders(
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          trakt: (id, type, current) => scoped(
            () => TraktService.instance.fetchTitleStatus(
              id,
              type,
              canContinue: current,
            ),
          ),
          simkl: (id, type, current) => scoped(
            () => SimklService.instance.fetchTitleStatus(
              id,
              contentType: type,
              canContinue: current,
            ),
          ),
          mdblist: (id, type, current) => scoped(
            () => MdblistService.instance.fetchTitleStatus(
              id,
              type,
              canContinue: current,
            ),
          ),
          recommendations: (id, type, current) => scoped(
            () => StremioService.instance.getRecommendations(
              imdbId: id,
              type: type,
              canContinue: current,
            ),
          ),
          metadata: (id, type, current) => scoped(
            () => StremioService.instance.fetchMetaDetails(
              imdbId: id,
              type: type,
              canContinue: current,
            ),
          ),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

/// One stateless dependency per originating profile; routes supply their guard.
final homeDetailActionsProvider = Provider.autoDispose
    .family<TrackerTitleActions, ProfileSessionOwner>(
      (ref, owner) => ProfileTrackerTitleActions(owner),
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeSourceEditingRepositoryProvider = Provider.autoDispose
    .family<HomeSourceEditingRepository, ProfileSessionOwner>(
      (ref, owner) => HomeSourceEditingRepository(owner),
      dependencies: const [],
    );

final homeCatalogOriginRepositoryProvider = Provider.autoDispose
    .family<HomeCatalogOriginRepository, ProfileSessionOwner>(
      (ref, owner) {
        bool current() => owner == ProfileSessionMemory.captureOwner();
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeCatalogOriginRepository(
          nativeAddon: NativeSeriesMetadataService.addon,
          isOwnerCurrent: current,
          scopeProgress: (item, addon, canContinue) => scoped(
            () => StremioService.instance.scopeSeriesProgress(
              item,
              addon,
              canContinue: () => current() && canContinue(),
            ),
          ),
          readCustomOrigin: (id) =>
              scoped(() => StremioService.instance.addonForCustomProgress(id)),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

/// Stateless per-owner adapter. Explicit actions retain the resolver and provide
/// their own live view/cancellation guard; factory disposal starts no teardown.
final homeCatalogEpisodeIdentityProvider = Provider.autoDispose
    .family<HomeCatalogEpisodeIdentity, ProfileSessionOwner>(
      (ref, owner) {
        return HomeCatalogEpisodeIdentity(
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          isCanonicalCatalog: StremioService.isCanonicalCatalogAlias,
          isCanonicalEpisode: StremioService.isCanonicalEpisodeId,
          readVideoId:
              ({
                required addon,
                required imdbId,
                required catalogId,
                required season,
                required episode,
              }) {
                Future<String?> read() =>
                    StremioService.instance.episodeVideoIdForLaunch(
                      addon: addon,
                      imdbId: imdbId,
                      catalogId: catalogId,
                      season: season,
                      episode: episode,
                    );
                final scope = owner.scope;
                return scope == null
                    ? read()
                    : ProfileRuntime.withCapturedScope(scope, read);
              },
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeTrackingPolicyRepositoryProvider = Provider.autoDispose
    .family<HomeTrackingPolicyRepository, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeTrackingPolicyRepository(
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          readTargets: (current) => scoped(
            () =>
                StorageService.getTrackingScrobbleTargets(canContinue: current),
          ),
          readProgress: () => scoped(StorageService.getWatchProgressSource),
          hasCredential: (source, current) => scoped(
            () => switch (source) {
              TrackingSource.trakt => StorageService.hasTraktCredential(
                canContinue: current,
              ),
              TrackingSource.simkl => StorageService.hasSimklCredential(
                canContinue: current,
              ),
              TrackingSource.mdblist => StorageService.hasMdblistCredential(
                canContinue: current,
              ),
              TrackingSource.local => Future.value(true),
            },
          ),
          fallbackDisconnected: (source, current) => scoped(
            () => StorageService.fallbackDisconnectedProgressSource(
              source,
              canContinue: current,
            ),
          ),
          readTicks: () => scoped(StorageService.getHomeTickSources),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
