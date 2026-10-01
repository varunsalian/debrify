import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/ambient_trailer_surface.dart';
import 'package:debrify/services/storage/ambient_trailer_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/imdb_trailer_service.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/metadata_provider_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_iptv_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/youtube_service.dart';
import '../../../theme/artwork_accent.dart';
import '../data/home_hero_live_repository.dart';
import '../data/home_hero_metadata_repository.dart';
import '../data/home_hero_trailer_repository.dart';
import '../data/home_trailer_preferences_repository.dart';
import '../models/home_catalog_session.dart';
import 'home_hero_live_preview.dart';
import 'home_hero_metadata_loader.dart';
import 'home_hero_tint_loader.dart';
import 'home_hero_trailer_loader.dart';
import 'home_hero_trailer_resolver.dart';
import 'home_spotlight_live_preview.dart';

final homeHeroLiveRepositoryProvider = Provider<HomeHeroLiveRepository>(
  (ref) => HomeHeroLiveRepository(
    isAddonChannel: StremioIptvService.isStremioChannelUrl,
    resolveCandidates: (key) =>
        StremioIptvService.instance.resolveCandidates(key),
    invalidate: StremioIptvService.instance.invalidate,
  ),
  dependencies: const [],
);

final homeHeroLivePreviewProvider = Provider.autoDispose
    .family<HomeHeroLivePreview, HomeCatalogSession>(
      (ref, session) {
        final preview = HomeHeroLivePreview(
          repository: ref.watch(homeHeroLiveRepositoryProvider),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(preview.dispose);
        return preview;
      },
      retry: (count, error) => null,
      dependencies: [homeHeroLiveRepositoryProvider],
    );

final homeHeroMetadataRepositoryProvider = Provider<HomeHeroMetadataRepository>(
  (ref) => HomeHeroMetadataRepository(
    readPreferences: (current) =>
        MetadataPreferencesService.loadForBackground(isCurrent: current),
    fetchDetails: (imdbId, type) =>
        StremioService.instance.fetchMetaDetails(imdbId: imdbId, type: type),
    present: (item, preferences, current) => MetadataProviderService.instance
        .present(item, preferences: preferences, isRelevant: current),
  ),
  dependencies: const [],
);

final homeHeroMetadataLoaderProvider = Provider.autoDispose
    .family<HomeHeroMetadataLoader, HomeCatalogSession>(
      (ref, session) {
        final loader = HomeHeroMetadataLoader(
          repository: ref.watch(homeHeroMetadataRepositoryProvider),
          captureScopeGuard: () {
            // Capture per request, at the same point as the original screen.
            final scope = ProfileRuntime.scope.value;
            return () => scope == ProfileRuntime.scope.value;
          },
        );
        ref.onDispose(loader.dispose);
        return loader;
      },
      retry: (count, error) => null,
      dependencies: [homeHeroMetadataRepositoryProvider],
    );

final homeHeroTintResolverProvider = Provider<HomeHeroTintResolver>(
  (ref) =>
      (poster) =>
          DominantColorCache.of(poster, CachedNetworkImageProvider(poster)),
  dependencies: const [],
);

final homeHeroTintLoaderProvider = Provider.autoDispose
    .family<HomeHeroTintLoader, HomeCatalogSession>(
      (ref, session) {
        final loader = HomeHeroTintLoader(
          resolve: ref.watch(homeHeroTintResolverProvider),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(loader.dispose);
        return loader;
      },
      retry: (count, error) => null,
      dependencies: [homeHeroTintResolverProvider],
    );

final homeHeroTrailerRepositoryProvider = Provider<HomeHeroTrailerRepository>(
  (ref) => HomeHeroTrailerRepository(
    readPreferences: (current) =>
        MetadataPreferencesService.loadForBackground(isCurrent: current),
    selectTrailers: (item, original, preferences) => MetadataProviderService
        .instance
        .trailers(item, original, preferences: preferences),
    fetchDetails: (imdbId, type) =>
        StremioService.instance.fetchMetaDetails(imdbId: imdbId, type: type),
    resolveYoutube: (id) => YoutubeService.resolveStreams(
      id,
      maxHeightOverride: YoutubeService.ambientTrailerMaxHeight,
      preferVp9: true,
    ),
    resolveImdb: (imdbId) => ImdbTrailerService.resolveTrailer(
      imdbId,
      maxHeight: YoutubeService.ambientTrailerMaxHeight,
    ),
  ),
  dependencies: const [],
);

final homeHeroTrailerResolverProvider = Provider<HomeHeroTrailerResolver>(
  (ref) =>
      HomeHeroTrailerResolver(ref.watch(homeHeroTrailerRepositoryProvider)),
  dependencies: [homeHeroTrailerRepositoryProvider],
);

final homeHeroTrailerLoaderProvider = Provider.autoDispose
    .family<HomeHeroTrailerLoader, HomeCatalogSession>(
      (ref, session) {
        final resolver = ref.watch(homeHeroTrailerResolverProvider);
        final loader = HomeHeroTrailerLoader(
          resolve: (item, current) =>
              resolver.resolve(item, isCurrent: current),
          captureScopeGuard: () {
            final scope = ProfileRuntime.scope.value;
            return () => scope == ProfileRuntime.scope.value;
          },
        );
        ref.onDispose(loader.dispose);
        return loader;
      },
      retry: (count, error) => null,
      dependencies: [homeHeroTrailerResolverProvider],
    );

final homeTrailerPreferencesRepositoryProvider =
    Provider<HomeTrailerPreferencesRepository>((ref) {
      AmbientTrailerSurface surface(bool useHomeAudio) => useHomeAudio
          ? AmbientTrailerSurface.homeHero
          : AmbientTrailerSurface.detail;
      return HomeTrailerPreferencesRepository(
        readEnabled: AmbientTrailerStorage.getHomeHeroTrailerEnabled,
        readAudioEnabled: (home) =>
            AmbientTrailerStorage.getAmbientTrailerAudioEnabled(surface(home)),
        readVolume: (home) =>
            AmbientTrailerStorage.getAmbientTrailerVolume(surface(home)),
      );
    }, dependencies: const []);

/// A preview is owned by its mounted card, independently of the parent board
/// or another card displaying the same channel.
HomeCatalogSession createHomeSpotlightLiveSession() => HomeCatalogSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);

final homeSpotlightLivePreviewProvider = Provider.autoDispose
    .family<HomeSpotlightLivePreview, HomeCatalogSession>(
      (ref, session) {
        final preview = HomeSpotlightLivePreview(
          repository: ref.watch(homeHeroLiveRepositoryProvider),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(preview.dispose);
        return preview;
      },
      retry: (count, error) => null,
      dependencies: [homeHeroLiveRepositoryProvider],
    );
