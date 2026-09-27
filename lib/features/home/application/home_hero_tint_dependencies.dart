import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../theme/artwork_accent.dart';
import '../models/home_catalog_session.dart';
import 'home_hero_tint_loader.dart';

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
