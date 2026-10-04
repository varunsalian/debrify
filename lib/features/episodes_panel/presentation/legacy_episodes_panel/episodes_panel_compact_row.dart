import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Compact Stremio-style episode row (merged series page) ───────────────────
class _CompactEpisodeRow extends StatefulWidget {
  final TraktEpisode episode;
  final String? showImageUrl;
  final bool isTelevision;
  final double? watchProgress; // 0..100
  final bool isNext;
  final FocusNode? focusNode;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final VoidCallback? onLeft;

  const _CompactEpisodeRow({
    required this.episode,
    required this.showImageUrl,
    required this.isTelevision,
    required this.watchProgress,
    required this.isNext,
    required this.focusNode,
    required this.onPlay,
    required this.onOptions,
    this.onLeft,
  });

  @override
  State<_CompactEpisodeRow> createState() => _CompactEpisodeRowState();
}

class _CompactEpisodeRowState extends State<_CompactEpisodeRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final progress = (widget.watchProgress ?? 0).clamp(0.0, 100.0);
    final watched = progress >= 100;
    final partial = progress > 5 && progress < 100;
    final thumbUrl = (e.thumbnailUrl?.isNotEmpty ?? false)
        ? e.thumbnailUrl
        : widget.showImageUrl;
    // The air date now has its own formatted meta line below the title, so the
    // description no longer falls back to the raw date string — it's overview
    // or nothing.
    final subtitle = (e.overview?.isNotEmpty ?? false) ? e.overview! : '';
    final airDate = e.formattedAirDate;
    // Some addons (e.g. Cinemeta) send `imdbRating: 0` for episodes that have no
    // rating rather than omitting it — treat 0/negative as "no rating" so we
    // don't render a meaningless ★ 0.0 on every episode.
    final rating = (e.rating != null && e.rating! > 0) ? e.rating : null;
    final hasMeta = (airDate != null && airDate.isNotEmpty) || rating != null;
    final t = DetailThemeScope.maybeOf(context);

    final row = Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
        if (f && widget.isTelevision && context.mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (isActivateKey(k) || k == LogicalKeyboardKey.space) {
          widget.onPlay();
          return KeyEventResult.handled;
        }
        // Episodes are the right-most pane, so Right is free — use it for the
        // per-episode options menu.
        if (k == LogicalKeyboardKey.arrowRight) {
          widget.onOptions();
          return KeyEventResult.handled;
        }
        // Left crosses to the host's info column — send it to a stable target
        // (the host's Play/source button) instead of a geometry-picked item.
        if (k == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
          widget.onLeft!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored; // Up/Down → directional focus
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPlay,
          onLongPress: widget.onOptions,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            // Snap the focus ring on TV (house idiom) — held-DPAD scrolling
            // otherwise animates two rows' fills/borders on every step.
            duration: widget.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused
                    ? t.focus
                    : Colors.white.withValues(alpha: 0.06),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 124,
                    height: 70,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbUrl != null && thumbUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: thumbUrl,
                            fit: BoxFit.cover,
                            // Long-lived shared cache — the 200-object default
                            // evicts these within one TV browsing session,
                            // forcing a re-download on every visit.
                            cacheManager: DebrifyImageCache.manager,
                            // 124-logical-px thumb — the show-poster fallback
                            // is a full-size poster; never decode it full-res
                            // for a row thumbnail (×N rows on a 2 GB box).
                            memCacheWidth: 300,
                            fadeInDuration: HomeTheme.imageFadeIn(
                              widget.isTelevision,
                            ),
                            fadeOutDuration: HomeTheme.imageFadeOut(
                              widget.isTelevision,
                            ),
                            // Solid fill while loading — without it the tile
                            // is a transparent hole until the bytes land.
                            placeholder: (_, __) =>
                                Container(color: const Color(0xFF1A1622)),
                            errorWidget: (_, __, ___) =>
                                Container(color: const Color(0xFF1A1622)),
                          )
                        else
                          Container(color: const Color(0xFF1A1622)),
                        if (watched)
                          Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: t.focus,
                              size: 24,
                            ),
                          ),
                        if (widget.isNext && !watched)
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: t.focus,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'UP NEXT',
                                style: TextStyle(
                                  color: Color(0xFF2A1E02),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        if (partial)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 3,
                              color: Colors.black.withValues(alpha: 0.5),
                              child: FractionallySizedBox(
                                widthFactor: progress / 100,
                                alignment: Alignment.centerLeft,
                                child: Container(color: t.focus),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.title.trim().isEmpty
                            ? 'Episode ${e.number}'
                            : '${e.number}. ${e.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      // IMDb rating + air date, mirroring the series-level meta
                      // bar in the left pane so each episode reads at a glance.
                      if (hasMeta) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (rating != null) ...[
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Color(0xFFFACC15),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFFFACC15),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (rating != null &&
                                airDate != null &&
                                airDate.isNotEmpty)
                              Text(
                                '  ·  ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                            if (airDate != null && airDate.isNotEmpty)
                              Text(
                                airDate,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Trailing: watch state + a PERSISTENT options affordance (so
                // even watched/in-progress rows still advertise ▶ = Options).
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (watched)
                      Icon(Icons.check_circle_rounded, color: t.focus, size: 18)
                    else if (partial)
                      Text(
                        '${progress.round()}%',
                        style: TextStyle(
                          color: t.focus,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (watched || partial) const SizedBox(width: 8),
                    if (widget.isTelevision)
                      // Brightens when the row is focused to hint "press ▶".
                      Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Colors.white.withValues(
                          alpha: _focused ? 0.9 : 0.35,
                        ),
                      )
                    else
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 20,
                        ),
                        onPressed: widget.onOptions,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // RepaintBoundary: a focus move repaints only the two rows whose ring
    // changed, not the whole episode column (thumbnails, scrims and all).
    return RepaintBoundary(child: row);
  }
}

typedef EpisodesPanelCompactRow = _CompactEpisodeRow;

const episodesPanelCompactRowConstructor = _CompactEpisodeRow.new;
