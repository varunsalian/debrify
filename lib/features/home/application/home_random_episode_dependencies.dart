import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../services/local_series_completion_service.dart';
import '../../../services/native_series_metadata_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_random_playback_repository.dart';

import '../../../services/stremio_service.dart';
import '../data/home_random_episode_selector.dart';

/// Stateless selection uses the same identity rules as ordinary playback.
final homeRandomEpisodeSelectorProvider = Provider<HomeRandomEpisodeSelector>(
  (ref) => HomeRandomEpisodeSelector(
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
