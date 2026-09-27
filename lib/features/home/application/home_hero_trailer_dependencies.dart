import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/imdb_trailer_service.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/metadata_provider_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/youtube_service.dart';
import '../data/home_hero_trailer_repository.dart';
import 'home_hero_trailer_resolver.dart';
import 'home_hero_trailer_loader.dart';
import '../models/home_catalog_session.dart';
import '../../../services/profiles/profile_runtime.dart';

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
