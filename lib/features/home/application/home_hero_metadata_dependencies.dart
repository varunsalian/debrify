import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/metadata_provider_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/stremio_service.dart';
import '../data/home_hero_metadata_repository.dart';
import '../models/home_catalog_session.dart';
import 'home_hero_metadata_loader.dart';

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
