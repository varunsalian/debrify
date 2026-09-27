import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_catalog_session.dart';
import 'home_hero_live_dependencies.dart';
import 'home_spotlight_live_preview.dart';

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
