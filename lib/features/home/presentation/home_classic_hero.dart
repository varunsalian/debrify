import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../application/home_stage_metadata.dart';
import 'home_hero_spotlight.dart';

/// Read at hero rebuild time, preserving live mode and artwork-budget changes
/// even when only focused/enriched metadata signals rebuild this subtree.
typedef HomeClassicHeroConfiguration = ({
  bool compact,
  bool isTelevision,
  int artworkCacheWidth,
  int? artworkCacheHeight,
  bool trailerActive,
});

/// Classic's focused hero and late metadata fallback. Signals are borrowed from
/// their existing owners; an empty focus does not subscribe to enriched data.
Widget buildHomeClassicHero({
  required ValueListenable<StremioMeta?> focused,
  required ValueListenable<StremioMeta?> enriched,
  required double height,
  required HomeClassicHeroConfiguration Function() readConfiguration,
  required ValueListenable<Color?> tint,
  required ValueListenable<bool> trailerShowing,
  required ValueListenable<bool> liveTakeover,
}) => ValueListenableBuilder<StremioMeta?>(
  valueListenable: focused,
  builder: (context, item, _) {
    if (item == null) return const SizedBox.shrink();
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: enriched,
      builder: (context, details, _) {
        final configuration = readConfiguration();
        return HomeHeroSpotlight(
          item: item,
          background: item.background?.isNotEmpty == true
              ? item.background
              : details?.background,
          description: item.description?.isNotEmpty == true
              ? item.description
              : details?.description,
          // Catalog lists often omit rating/runtime and title-treatment art.
          rating: item.imdbRating ?? details?.imdbRating,
          runtime: item.runtimeDisplay ?? details?.runtimeDisplay,
          // Start IMDb title art before /meta arrives; its resolved URL is
          // normally the same, avoiding an unnecessary later artwork swap.
          logo: item.logo?.isNotEmpty == true
              ? item.logo
              : (details?.logo?.isNotEmpty == true
                    ? details!.logo
                    : homeStageLogoUrl(item)),
          compact: configuration.compact,
          isTelevision: configuration.isTelevision,
          height: height,
          artworkCacheWidth: configuration.artworkCacheWidth,
          artworkCacheHeight: configuration.artworkCacheHeight,
          tint: tint,
          // The synchronous Home layout chooses the boxed region. Async trailer
          // preferences only gate playback: trailers-off keeps the same key art
          // and identity geometry instead of flipping the layout after startup.
          boxedTrailer: configuration.trailerActive,
          // Loading UI lives in the trailer region. Showing still freezes the
          // backdrop drift; a live channel hides the stale catalog identity.
          trailerLoading: null,
          trailerShowing: configuration.trailerActive ? trailerShowing : null,
          liveTakeover: configuration.trailerActive ? liveTakeover : null,
        );
      },
    );
  },
);
