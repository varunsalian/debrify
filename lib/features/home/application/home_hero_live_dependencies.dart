import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_iptv_service.dart';
import '../data/home_hero_live_repository.dart';
import '../models/home_catalog_session.dart';
import 'home_hero_live_preview.dart';

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
