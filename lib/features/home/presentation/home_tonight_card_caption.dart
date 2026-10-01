import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/hero_metadata_presentation.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../application/home_stage_metadata.dart';
import '../application/home_tonight_caption_policy.dart';
import '../models/home_tonight_card_info.dart';
import 'home_favorite_focus.dart';

/// The caption block on Tonight's card: title art, what you are about to do,
/// the episode, how much is left and the progress bar. Everything is driven
/// by listenables so a DPAD move repaints this block alone.
class HomeTonightCardCaption extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final ValueListenable<HomeFavoriteFocus?> fav;
  final ValueListenable<HomeTonightCardInfo?> info;

  const HomeTonightCardCaption({
    super.key,
    required this.item,
    required this.enriched,
    required this.fav,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    // Hoisted: `fav` fires on every focus move across the Tonight rail.
    final tx = AppThemeScope.of(context).core.tx;
    return ValueListenableBuilder<HomeFavoriteFocus?>(
      valueListenable: fav,
      builder: (context, favFocus, _) {
        if (favFocus != null) {
          return _block(
            context,
            hold: null,
            titleWidget: Text(
              favFocus.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tx,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
              ),
            ),
            line: favFocus.subtitle,
            action: 'Watch',
            progress: null,
          );
        }
        return ValueListenableBuilder<StremioMeta?>(
          valueListenable: item,
          builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
            valueListenable: enriched,
            builder: (context, en, _) =>
                ValueListenableBuilder<HomeTonightCardInfo?>(
                  valueListenable: info,
                  builder: (context, nfo, _) {
                    final it0 = it;
                    if (it0 == null) return const SizedBox.shrink();
                    final enr = (en != null && sameHomeStageTitle(it0, en))
                        ? en
                        : null;
                    final fields = HeroMetadataFields(it0, enr);
                    final logo =
                        fields.logo ??
                        (fields.allowArtworkFallback
                            ? homeStageLogoUrl(it0)
                            : null);
                    final runtime = fields.runtime;
                    final left = homeTonightTimeLeft(runtime, nfo?.progress);
                    final parts = <String>[
                      if (nfo?.episode != null) nfo!.episode!,
                      if (left != null) left else if (runtime != null) runtime,
                      if (nfo?.episode == null && left == null)
                        (it0.type == 'series' ? 'SERIES' : 'MOVIE'),
                    ];
                    return _block(
                      context,
                      hold: nfo?.holdAction,
                      titleWidget: logo != null
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 46,
                                maxWidth: 300,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: logo,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                memCacheWidth: 400,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) =>
                                    const SizedBox(height: 46),
                                errorWidget: (_, __, ___) =>
                                    _fallbackTitle(fields.name),
                              ),
                            )
                          : _fallbackTitle(fields.name),
                      line: parts.join('  ·  '),
                      action: nfo?.action ?? 'Open',
                      progress: nfo?.progress,
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  static Widget _fallbackTitle(String name) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
    ),
  );

  Widget _block(
    BuildContext context, {
    required Widget titleWidget,
    required String line,
    required String action,
    required String? hold,
    required double? progress,
  }) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.74),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (hold != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: app.fade(app.core.tx, 0.30)),
                  borderRadius: app.shape.br(20),
                ),
                child: Text(
                  'HOLD  $hold',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: app.core.tx.withValues(alpha: 0.92),
                borderRadius: app.shape.br(20),
              ),
              child: Text(
                'OK  $action',
                style: const TextStyle(
                  color: Color(0xFF12101F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        if (progress != null && progress > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: app.shape.br(3),
            child: SizedBox(
              height: 5,
              child: ColoredBox(
                color: app.core.tx.withValues(alpha: 0.22),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
