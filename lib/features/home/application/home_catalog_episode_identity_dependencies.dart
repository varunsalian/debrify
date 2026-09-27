import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_service.dart';
import '../data/home_catalog_episode_identity.dart';

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
