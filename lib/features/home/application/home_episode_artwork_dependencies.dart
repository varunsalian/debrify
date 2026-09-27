import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/episode_artwork_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_episode_artwork_repository.dart';
import '../models/home_catalog_session.dart';

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
