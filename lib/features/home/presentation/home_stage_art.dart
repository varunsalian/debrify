import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/hero_metadata_presentation.dart';
import '../../../theme/app_theme_scope.dart';
import '../application/home_stage_metadata.dart';
import '../application/home_stage_art_failures.dart';
import 'home_favorite_focus.dart';

// Shared across stage views for the original process/session lifetime.
final _backdropFailures = HomeStageArtFailures();

/// Canvas stage floor + full-bleed key art for the settled hero item. Sits
/// BELOW the underlay punch hole; the AnimatedSwitcher fade wraps only this
/// sibling, never the engine, so the hole's BlendMode.clear is untouched.
class HomeStageArt extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final int cacheWidth;
  final int cacheHeight;

  /// Non-null while a favourites cell has focus: its art overrides the hero
  /// pipeline's (contain-fit logos render centred over the floor instead of
  /// being cover-stretched across the canvas).
  final ValueListenable<HomeFavoriteFocus?> fav;

  const HomeStageArt({
    super.key,
    required this.item,
    required this.enriched,
    required this.fav,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) => ValueListenableBuilder<HomeFavoriteFocus?>(
          valueListenable: fav,
          builder: (context, fav, _) {
            // Enrichment merged over the catalog item: matched by canonical
            // IMDb identity (ids can differ in form), and a sparse /meta
            // record can't erase a backdrop the catalog already carried.
            final enr = (it != null && en != null && sameHomeStageTitle(it, en))
                ? en
                : null;
            // WIDE art first. The old chain fell straight from "no backdrop"
            // to the POSTER, which a 16:9 box has to crop to a horizontal
            // slice — on a title whose poster is a row of character portraits
            // that reads as several unrelated images stacked in one card. The
            // metahub still (derived synchronously from the IMDb id, exactly
            // like the title logo) is a real landscape frame and exists for
            // most titles; the poster stays as the last resort, applied by the
            // error branch below so a 404 still lands on something.
            final fields = it == null ? null : HeroMetadataFields(it, enr);
            final wide = it == null
                ? null
                : fields!.background ??
                      (!fields.allowArtworkFallback ||
                              _backdropFailures.contains(
                                homeStageBackgroundUrl(it) ?? '',
                              )
                          ? null
                          : homeStageBackgroundUrl(it));
            final posterUrl = fields?.posterFallback;
            final bg = wide ?? posterUrl ?? '';
            final Widget art;
            final favArt = fav?.art;
            if (fav != null) {
              if (favArt == null || favArt.isEmpty) {
                art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
              } else if (fav.fit == BoxFit.contain) {
                art = Center(
                  key: ValueKey('canvas-fav-logo-$favArt'),
                  child: FractionallySizedBox(
                    widthFactor: 0.38,
                    heightFactor: 0.38,
                    child: CachedNetworkImage(
                      imageUrl: favArt,
                      fit: BoxFit.contain,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                );
              } else {
                art = CachedNetworkImage(
                  key: ValueKey(
                    'canvas-fav-art-$favArt-${cacheWidth}x$cacheHeight',
                  ),
                  imageUrl: favArt,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: cacheWidth,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
              }
            } else if (bg.isEmpty) {
              art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
            } else {
              // A derived metahub still can 404 (not every title has one).
              // Remember that so the next focus doesn't ask again, and fall
              // back to the poster in place rather than to an empty stage.
              final derived =
                  wide != null &&
                  wide != enr?.background &&
                  wide != it?.background;
              art = CachedNetworkImage(
                key: ValueKey('$bg-${cacheWidth}x$cacheHeight'),
                imageUrl: bg,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: wide != null ? cacheWidth : null,
                memCacheHeight: wide == null ? cacheHeight : null,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) {
                  if (derived) _backdropFailures.remember(bg);
                  if (posterUrl == null || bg == posterUrl) {
                    return const SizedBox.shrink();
                  }
                  return CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    memCacheHeight: cacheHeight,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  );
                },
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                // Opaque floor: the app shell can never show through a missing
                // or still-decoding backdrop.
                ColoredBox(color: app.home.bg),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  // AnimatedSwitcher's DEFAULT layout centres its children under
                  // LOOSE constraints, so a BoxFit.cover image sizes to its own
                  // aspect instead of the box. On Canvas the box is the whole
                  // 16:9 screen and it looked identical either way — but Atrium's
                  // art column is nearly square, and there the backdrop
                  // letterboxed with ink bands above and below it. Expand both
                  // the incoming and outgoing child so "cover" means the box.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: art,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
