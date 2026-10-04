import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/services/trakt/trakt_episode_model.dart'
    show TraktEpisode;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';

// ── episodes ───────────────────────────────────────────────────────────────

/// The still, then the caption BELOW it — and the focused cell gets a plate
/// behind the whole thing, still and text together.
class ShowcaseEpisodeCell extends StatelessWidget {
  final TraktEpisode episode;
  final double? cellWidth;
  final double? stillWidth;
  final double? stillHeight;
  final bool focused;
  final double? progress;
  final bool isNext;
  final String? fallbackImage;

  /// Touch/pointer surfaces only: a visible ⋮ over the still, the discoverable
  /// stand-in for hold-OK. TV passes null and renders exactly as before.
  final VoidCallback? onOptions;

  const ShowcaseEpisodeCell({
    super.key,
    required this.episode,
    required this.focused,
    required this.progress,
    required this.isNext,
    required this.fallbackImage,
    this.cellWidth,
    this.stillWidth,
    this.stillHeight,
    this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress ?? 0;
    final watched = p >= 100;
    final url = ViewportArtworkScope.enabledOf(context)
        ? episode.thumbnailUrl ?? fallbackImage
        : null;

    final m = ShowcaseMetrics.of(context);
    // The plate goes behind the CAPTION, not around the whole cell.
    //
    // A fill around everything sits behind the still too, where it is invisible
    // under the artwork and only shows as a hairline margin — so the focused
    // cell read as barely distinguishable. In the reference the still carries
    // focus by lifting, and the caption below it gains a filled card. Splitting
    // them lets each do its own job.
    final slot = sSlotFill(AppThemeScope.of(context));
    return SizedBox(
      width: cellWidth ?? m.epCell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ParallaxFocus(
            focused: focused,
            shape: ParallaxShape.episodeStill,
            radius: BorderRadius.circular(6),
            child: SizedBox(
              width: stillWidth ?? m.stillW,
              height: stillHeight ?? m.stillH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null && url.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        cacheManager: DebrifyImageCache.manager,
                        memCacheWidth: 500,
                        placeholder: (_, __) => ColoredBox(color: slot),
                        errorWidget: (_, __, ___) => ColoredBox(color: slot),
                      )
                    else
                      ColoredBox(color: slot),
                    if (watched)
                      ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                    if (isNext && !watched)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _Badge(label: 'UP NEXT'),
                      ),
                    if (watched)
                      const Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    if (p > 0 && p < 100)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: p / 100,
                          minHeight: 2,
                          backgroundColor: Colors.black.withValues(alpha: 0.4),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    if ((episode.runtime ?? 0) > 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: _Badge(label: '▶ ${episode.runtime}m'),
                      ),
                    if (onOptions != null)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: _KebabButton(onTap: onOptions!),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            // Padded on BOTH states, so gaining the plate does not shift the
            // text sideways — only its ground appears.
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            decoration: BoxDecoration(
              color: focused ? sInk.withValues(alpha: 0.13) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rating rides the eyebrow in the same small-caps monochrome
                // grammar (the _SeverityMark rule: no colored chips against
                // the artwork). Trakt backfills ratings addons omit — see
                // EpisodesPanel._enrichEpisodeRatings — and 0 means unrated.
                Text(
                  (episode.rating ?? 0) > 0
                      ? 'EPISODE ${episode.number} · ★ '
                            '${episode.rating!.toStringAsFixed(1)}'
                      : 'EPISODE ${episode.number}',
                  style: st(9.5 * m.k, a: 0.55).copyWith(letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st(12.5 * m.k, w: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 29 * m.k,
                  child: Text(
                    episode.overview ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: st(10.5 * m.k, a: 0.6).copyWith(height: 1.36),
                  ),
                ),
                if ((episode.firstAired ?? '').isNotEmpty)
                  Text(
                    episode.firstAired!.split('T').first,
                    style: st(9.5 * m.k, a: 0.5),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact episode card — one integrated rounded rect: still on top,
/// caption plate inside the same card (eyebrow, title, three-line synopsis,
/// runtime + kebab). The measured Apple phone idiom: ~62% of the width, next
/// card peeking. Tap-to-play and the focus lift are supplied by the
/// `DetailEpisodeInteraction` wrapper, exactly as for the wide cell.
class ShowcaseEpisodeCardCompact extends StatelessWidget {
  final TraktEpisode episode;
  final bool focused;
  final double? progress;
  final bool isNext;
  final String? fallbackImage;
  final VoidCallback onOptions;

  const ShowcaseEpisodeCardCompact({
    super.key,
    required this.episode,
    required this.focused,
    required this.progress,
    required this.isNext,
    required this.fallbackImage,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final app = AppThemeScope.of(context);
    final p = progress ?? 0;
    final watched = p >= 100;
    final url = ViewportArtworkScope.enabledOf(context)
        ? episode.thumbnailUrl ?? fallbackImage
        : null;
    final slot = sSlotFill(app);

    return ParallaxFocus(
      focused: focused,
      shape: ParallaxShape.episodeStill,
      radius: BorderRadius.circular(12),
      child: SizedBox(
        width: m.epCell,
        height: m.stillH + m.epPlate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No card fill: still + caption sit straight on the page, the
            // wide/TV cell's anatomy (user call 2026-08-16 — the solid
            // integrated card read as a foreign object on a board where
            // every other surface is the page). The still carries its own
            // full rounded clip now; under the old whole-card clip its
            // bottom corners were squared off against the plate below.
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: m.epCell,
                height: m.stillH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null && url.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        cacheManager: DebrifyImageCache.manager,
                        memCacheWidth: 500,
                        placeholder: (_, __) => ColoredBox(color: slot),
                        errorWidget: (_, __, ___) => ColoredBox(color: slot),
                      ),
                    if (watched)
                      ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                    if (isNext && !watched)
                      Positioned(
                        left: 7,
                        top: 7,
                        child: _Badge(label: 'UP NEXT'),
                      ),
                    if (watched)
                      const Positioned(
                        right: 7,
                        top: 7,
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    if (p > 0 && p < 100)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: p / 100,
                          minHeight: 3,
                          backgroundColor: Colors.black.withValues(alpha: 0.4),
                          valueColor: AlwaysStoppedAnimation(app.core.accent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                // The wide/TV cell's answer to focus, echoed here for the
                // scroll-settled card: the caption gains an ink plate while
                // the still lifts. Padded identically in BOTH states so
                // gaining the plate never shifts the text — only its ground
                // appears (the wide cell's own rule).
                decoration: BoxDecoration(
                  color: focused ? sInk.withValues(alpha: 0.13) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                // Near-flush with the still's edge — page text, not card
                // text, now that the resting fill is gone.
                padding: const EdgeInsets.fromLTRB(8, 9, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EPISODE ${episode.number}',
                      style: st(10, a: 0.5).copyWith(letterSpacing: 0.9),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: st(14.5, w: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      // Whole lines only. maxLines guards the HORIZONTAL
                      // overflow of the last permitted line — it does nothing
                      // about the box being 2.6 line-heights tall, which
                      // sliced the third line through its middle. Fit the
                      // line count to the height that actually exists
                      // (text-scale aware), and the last line ends in an
                      // ellipsis instead of a crop.
                      child: LayoutBuilder(
                        builder: (context, c) {
                          const fs = 11.5;
                          final line =
                              MediaQuery.textScalerOf(context).scale(fs) * 1.4;
                          final lines = (c.maxHeight / line).floor().clamp(
                            1,
                            3,
                          );
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              episode.overview ?? '',
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              style: st(fs, a: 0.55).copyWith(height: 1.4),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        if ((episode.runtime ?? 0) > 0) ...[
                          const Icon(
                            Icons.play_arrow_rounded,
                            size: 13,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 3),
                          Text('${episode.runtime}m', style: st(11.5, a: 0.7)),
                        ] else if ((episode.firstAired ?? '').isNotEmpty)
                          Text(
                            episode.firstAired!.split('T').first,
                            style: st(11.5, a: 0.5),
                          ),
                        // Same monochrome footer grammar as the runtime.
                        if ((episode.rating ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '★ ${episode.rating!.toStringAsFixed(1)}',
                            style: st(11.5, a: 0.7),
                          ),
                        ],
                        const Spacer(),
                        _KebabButton(onTap: onOptions),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The visible stand-in for hold-OK on touch surfaces: ⋮ with a real finger
/// target behind a small glyph.
class _KebabButton extends StatelessWidget {
  final VoidCallback onTap;
  const _KebabButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.all(6 * k),
        child: Icon(
          Icons.more_vert_rounded,
          size: 17 * k,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(3.5 * k),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 5 * k, vertical: 2 * k),
        child: Text(label, style: st(9.5 * k)),
      ),
    );
  }
}
