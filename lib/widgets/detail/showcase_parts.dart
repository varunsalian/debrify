import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/services/imdb_enrichment_service.dart'
    show CastMember, UniverseTitle, DidYouKnowEntry;
import 'package:debrify/services/imdb_parents_guide_service.dart'
    show ParentsGuideResult, ParentsGuideCategory, ParentsGuideItem;
import 'package:debrify/services/series_source_service.dart' show SeriesSource;
import 'package:debrify/services/trakt/trakt_episode_model.dart'
    show TraktEpisode;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:debrify/widgets/season_action_region.dart';
import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';

export 'package:debrify/features/detail_showcase/presentation/showcase_grounds.dart'
    show ShowcaseAmbient, ShowcaseBackdropScrim, ShowcaseStickyLogo;
export 'package:debrify/features/detail_showcase/presentation/showcase_identity.dart'
    show ShowcaseIdentity;
export 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart'
    show ShowcaseMetrics, ShowcaseMetricsScope, kShowcaseGutter;

// ── seasons ────────────────────────────────────────────────────────────────

class ShowcaseSeasons extends StatelessWidget {
  final EpisodesPanelView view;
  final List<FocusNode> nodes;

  const ShowcaseSeasons({super.key, required this.view, required this.nodes});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    // Compact: one pill + an anchored popup — Apple's phone idiom, measured
    // off the reference (no scrim, no sheet, the page stays live behind it).
    // The band carries exactly ONE node then, supplied by the layout.
    if (m.compact) {
      return Padding(
        padding: EdgeInsets.only(left: m.gutter, right: m.gutter, top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _SeasonDropdown(view: view, node: nodes.first),
        ),
      );
    }
    return SizedBox(
      height: 34 * m.k,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: view.seasons.length,
        separatorBuilder: (_, __) => SizedBox(width: 7 * m.k),
        itemBuilder: (context, i) {
          final s = view.seasons[i];
          final active = s.number == view.selectedSeasonNumber;
          return _SeasonPill(
            node: nodes[i],
            label: 'Season ${s.number}',
            active: active,
            onTap: () => view.selectSeason(s.number),
            onOptions: view.seasonOptions == null
                ? null
                : () => view.seasonOptions!(s.number),
          );
        },
      ),
    );
  }
}

/// The compact season control: a tinted pill that opens an anchored popup
/// menu at its own position. `showMenu` supplies the parts a hand-rolled
/// overlay always forgets — outside-tap dismissal, Escape/Back, viewport-edge
/// repositioning, an internal scroll past ~8 seasons — and returns focus to
/// the anchor's route when it closes.
class _SeasonDropdown extends StatefulWidget {
  final EpisodesPanelView view;
  final FocusNode node;

  const _SeasonDropdown({required this.view, required this.node});

  @override
  State<_SeasonDropdown> createState() => _SeasonDropdownState();
}

class _SeasonDropdownState extends State<_SeasonDropdown> {
  bool _f = false;

  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - 220,
        0,
      ),
      color: const Color(0xFF1B1B1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 200, maxHeight: 380),
      items: [
        for (final s in widget.view.seasons)
          PopupMenuItem<int>(
            value: s.number,
            child: Text(
              'Season ${s.number}',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: s.number == widget.view.selectedSeasonNumber
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: s.number == widget.view.selectedSeasonNumber
                    ? AppThemeScope.of(context).core.accent
                    : Colors.white,
              ),
            ),
          ),
      ],
    );
    if (selected != null) widget.view.selectSeason(selected);
  }

  @override
  Widget build(BuildContext context) {
    return SeasonActionRegion(
      onTap: _open,
      onOptions: widget.view.seasonOptions == null
          ? null
          : () => widget.view.seasonOptions!(widget.view.selectedSeasonNumber),
      child: Focus(
        focusNode: widget.node,
        onFocusChange: (v) => setState(() => _f = v),
        onKeyEvent: (_, e) => widget.view.seasonOptions == null
            ? sActivate(e, _open)
            : KeyEventResult.ignored,
        child: GestureDetector(
          onTap: _open,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: sInk.withValues(alpha: _f ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Season ${widget.view.selectedSeasonNumber}',
                  style: st(14, w: FontWeight.w600),
                ),
                const SizedBox(width: 7),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonPill extends StatefulWidget {
  final FocusNode node;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onOptions;

  const _SeasonPill({
    required this.node,
    required this.label,
    required this.active,
    required this.onTap,
    this.onOptions,
  });

  @override
  State<_SeasonPill> createState() => _SeasonPillState();
}

class _SeasonPillState extends State<_SeasonPill> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return SeasonActionRegion(
      onTap: widget.onTap,
      onOptions: widget.onOptions,
      child: Focus(
        focusNode: widget.node,
        onFocusChange: (v) {
          setState(() => _f = v);
          if (v) sKeepVisible(context);
        },
        // Selecting on FOCUS would reload the episode list on every step of a
        // walk across the seasons. OK commits; the walk is free.
        onKeyEvent: (_, e) => widget.onOptions == null
            ? sActivate(e, widget.onTap)
            : KeyEventResult.ignored,
        // The wide row is what every TOUCH tablet gets (compact swaps in the
        // dropdown below 600), so the pill needs a finger path too — OK-only
        // left the season control dead under a finger. Opaque: the pill draws
        // no background until it is focused or active, and a bare DecoratedBox
        // defers the hit test to the Text, so the padding would miss.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ParallaxFocus(
            focused: _f,
            shape: ParallaxShape.pill,
            radius: BorderRadius.circular(12.5 * k),
            child: Container(
              height: 25 * k,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: 15 * k),
              decoration: BoxDecoration(
                color: (_f || widget.active)
                    ? sInk.withValues(alpha: _f ? 0.28 : 0.18)
                    : null,
                borderRadius: BorderRadius.circular(12.5 * k),
              ),
              child: Text(
                widget.label,
                style: st(
                  12.5 * k,
                  w: FontWeight.w600,
                  a: widget.active || _f ? 1 : 0.55,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

// ── cast ───────────────────────────────────────────────────────────────────

class ShowcaseCast extends StatelessWidget {
  final List<CastMember> cast;
  final List<FocusNode> nodes;
  final ValueChanged<CastMember>? onPersonOpen;

  const ShowcaseCast({
    super.key,
    required this.cast,
    required this.nodes,
    this.onPersonOpen,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return SBand(
      title: 'Cast & Crew',
      height: m.circle * 1.08 + 46 * m.k,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: cast.length,
        separatorBuilder: (_, __) => SizedBox(width: m.castGap),
        itemBuilder: (context, i) => _CastTile(
          member: cast[i],
          node: nodes[i],
          size: m.circle,
          onTap: onPersonOpen != null && (cast[i].tmdbPersonId ?? 0) > 0
              ? () => onPersonOpen!(cast[i])
              : null,
        ),
      ),
    );
  }
}

class _CastTile extends StatefulWidget {
  final CastMember member;
  final FocusNode node;
  final double size;
  final VoidCallback? onTap;

  const _CastTile({
    required this.member,
    required this.node,
    required this.size,
    this.onTap,
  });

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final url = ViewportArtworkScope.enabledOf(context)
        ? widget.member.imageUrl
        : null;
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, event) => sActivate(event, widget.onTap),
      child: Semantics(
        button: widget.onTap != null,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: SHover(
            cursor: widget.onTap != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            builder: (context, hovered) => SizedBox(
              width: widget.size,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParallaxFocus(
                    focused: _f || hovered,
                    shape: ParallaxShape.castCircle,
                    radius: BorderRadius.circular(widget.size / 2),
                    child: ClipOval(
                      child: SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: (url != null && url.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                cacheManager: DebrifyImageCache.manager,
                                memCacheWidth: 260,
                                placeholder: (_, __) =>
                                    const ColoredBox(color: Color(0xFF4A4A55)),
                                errorWidget: (_, __, ___) =>
                                    const ColoredBox(color: Color(0xFF4A4A55)),
                              )
                            : const ColoredBox(color: Color(0xFF4A4A55)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    widget.member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: st(12.5 * k),
                  ),
                  if ((widget.member.character ?? '').isNotEmpty)
                    Text(
                      widget.member.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: st(11.5 * k, a: 0.55),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── sources ────────────────────────────────────────────────────────────────

/// The Sources band — this page's "How to Watch".
///
/// Painted from BOUND sources, which are a SharedPreferences read, so the band
/// costs no network on open. Bind stops being a mystery button in the identity
/// row and becomes an action on the card it applies to.
class ShowcaseSources extends StatelessWidget {
  final List<SeriesSource> sources;
  final List<FocusNode> nodes;
  final VoidCallback? onOpen;

  /// The full browse/search source list (movies: a tap there PLAYS) or the
  /// season-pack search (series). When non-null the band gets a second entry
  /// card after "Pin source", and the layout supplies one extra node —
  /// topology always matches rendering.
  final VoidCallback? onBrowseAll;

  /// What that second entry card says — the layout words it per type,
  /// because a series' browse lands on the pack search, not "all sources".
  final String browseAllLabel;

  const ShowcaseSources({
    super.key,
    required this.sources,
    required this.nodes,
    required this.onOpen,
    this.onBrowseAll,
    this.browseAllLabel = '⌕  Browse all',
  });

  @override
  Widget build(BuildContext context) => SBand(
    title: 'Sources',
    height: 96 * ShowcaseMetrics.of(context).k,
    child: ListView.separated(
      clipBehavior: Clip.none,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        horizontal: ShowcaseMetrics.of(context).gutter,
      ),
      itemCount: 2 + (onBrowseAll != null ? 1 : 0),
      separatorBuilder: (_, __) =>
          SizedBox(width: ShowcaseMetrics.of(context).srcGap),
      itemBuilder: (context, i) {
        if (i == 1) {
          return _SourceCard(node: nodes[i], onTap: onOpen, add: true);
        }
        if (i == 2) {
          return _SourceCard(
            node: nodes[i],
            onTap: onBrowseAll,
            add: true,
            addLabel: browseAllLabel,
          );
        }
        return _SourceCard(
          node: nodes[i],
          onTap: onOpen,
          sourceCount: sources.length,
        );
      },
    ),
  );
}

class _SourceCard extends StatefulWidget {
  final FocusNode node;
  final int sourceCount;
  final bool add;

  /// The add-style card's label. Defaults to the binding manager's wording —
  /// a tap there PINS a source to the title, it doesn't play one, so the tile
  /// says "Pin source"; "Find sources" oversold it as a search.
  final String addLabel;
  final VoidCallback? onTap;

  const _SourceCard({
    required this.node,
    required this.onTap,
    this.sourceCount = 0,
    this.add = false,
    this.addLabel = '＋  Pin source',
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final mm = ShowcaseMetrics.of(context);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, e) => sActivate(e, widget.onTap),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: widget.onTap,
          // Same reason as `_Poster`: the Sources band is 96 tall to leave
          // the lift room, and the tight cross-axis constraint would stretch
          // this 66pt card to fill it.
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              shape: ParallaxShape.sourceCard,
              radius: BorderRadius.circular(7 * mm.k),
              child: Container(
                // Wide keeps the shipped 280/150 (k-scaled off TV); compact
                // grows the bound card to 75% of the width (the mock's
                // source card) and the add chip a touch for fingers.
                width: () {
                  if (!mm.compact) {
                    return (widget.add ? 150.0 : 280.0) * mm.k;
                  }
                  return widget.add ? 160.0 : mm.srcW;
                }(),
                height: 66 * mm.k,
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * mm.k,
                  vertical: 9 * mm.k,
                ),
                decoration: BoxDecoration(
                  color: widget.add ? null : sInk.withValues(alpha: 0.07),
                  border: Border.all(
                    color: sInk.withValues(alpha: widget.add ? 0.22 : 0.09),
                  ),
                  borderRadius: BorderRadius.circular(7 * mm.k),
                ),
                child: widget.add
                    ? Center(
                        child: Text(
                          widget.addLabel,
                          style: st(10.5 * mm.k, a: 0.66),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Pinned sources (${widget.sourceCount})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: st(10.5 * mm.k, w: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.sourceCount == 0
                                      ? 'Pin a source to get started'
                                      : 'View and manage sources',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: st(9.5 * mm.k, a: 0.58),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── more like this ─────────────────────────────────────────────────────────

class ShowcaseRecs extends StatelessWidget {
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final void Function(StremioMeta)? onTap;

  const ShowcaseRecs({
    super.key,
    required this.items,
    required this.nodes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return SBand(
      title: 'More Like This',
      height: m.posterH * 1.10 + 24,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: m.posterGap),
        itemBuilder: (context, i) => _Poster(
          item: items[i],
          node: nodes[i],
          onTap: onTap,
          width: m.poster,
          height: m.posterH,
        ),
      ),
    );
  }
}

class _Poster extends StatefulWidget {
  final StremioMeta item;
  final FocusNode node;
  final void Function(StremioMeta)? onTap;
  final double width;
  final double height;

  const _Poster({
    required this.item,
    required this.node,
    required this.onTap,
    required this.width,
    required this.height,
  });

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final url = ViewportArtworkScope.enabledOf(context)
        ? widget.item.poster
        : null;
    final slot = sSlotFill(AppThemeScope.of(context));
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, e) => sActivate(e, () => widget.onTap?.call(widget.item)),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: () => widget.onTap?.call(widget.item),
          // The band is taller than the card so the lift has somewhere to go,
          // and a horizontal ListView constrains its children to that height
          // TIGHTLY — without an Align the poster is stretched to the band
          // while its width stays `m.poster`, drawing a 2:3 poster at about
          // 0.53:1.
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              radius: BorderRadius.circular(7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: (url != null && url.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          memCacheWidth: 300,
                          placeholder: (_, __) => ColoredBox(color: slot),
                          errorWidget: (_, __, ___) => ColoredBox(color: slot),
                        )
                      : ColoredBox(color: slot),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── parents guide ──────────────────────────────────────────────────────────

List<ParentsGuideItem> _plainOf(ParentsGuideCategory c) => [
  for (final i in c.items)
    if (!i.isSpoiler) i,
];

List<ParentsGuideItem> _spoilersOf(ParentsGuideCategory c) => [
  for (final i in c.items)
    if (i.isSpoiler) i,
];

/// Severity level for the four-segment meter. Unknown wordings render the
/// word with an empty meter rather than guessing a level.
int _severityLevel(String severity) => switch (severity.toLowerCase()) {
  'none' => 1,
  'mild' => 2,
  'moderate' => 3,
  'severe' => 4,
  _ => 0,
};

/// Small-caps severity word plus the segment meter — monochrome, per the
/// approved mock: no traffic-light chips against the artwork.
class _SeverityMark extends StatelessWidget {
  final String severity;

  const _SeverityMark({required this.severity});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    final level = _severityLevel(severity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          severity.toUpperCase(),
          style: st(
            compact ? 9.5 : 7.5 * m.k,
            w: FontWeight.w700,
            a: 0.6,
          ).copyWith(letterSpacing: 1.0),
        ),
        SizedBox(width: compact ? 8 : 6 * m.k),
        for (var i = 1; i <= 4; i++) ...[
          Container(
            width: compact ? 10 : 8 * m.k,
            height: compact ? 3.5 : 3 * m.k,
            decoration: BoxDecoration(
              color: sInk.withValues(alpha: i <= level ? 0.88 : 0.16),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 4) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

/// The Parents Guide band — one focus node per category, exactly.
///
/// Wide: a rail of category cards with a plate below that FOLLOWS the
/// selected card (focus on DPAD, tap on pointer) — the season rail's
/// follow-focus pattern. SELECT on the selected card toggles that category's
/// spoiler entries, so expansion never changes the node count.
///
/// Compact: the same categories as full-width accordion rows in the
/// integrated-card style, tap to expand.
///
/// Spoiler entries are WITHHELD, not blurred: a live blur is a per-frame
/// raster cost the Android TV GLES2 path cannot afford, and unrendered text
/// is also the only spoiler treatment that can't be defeated by a screenshot
/// mid-fade. Selection and spoiler state live HERE, not in the layout — the
/// layout owns only the nodes, which is all the DPAD ladder needs.
class ShowcaseGuide extends StatefulWidget {
  final ParentsGuideResult guide;
  final List<FocusNode> nodes;
  final Color accent;

  const ShowcaseGuide({
    super.key,
    required this.guide,
    required this.nodes,
    required this.accent,
  });

  @override
  State<ShowcaseGuide> createState() => _ShowcaseGuideState();
}

class _ShowcaseGuideState extends State<ShowcaseGuide> {
  int _sel = 0;

  /// Wide: spoilers revealed for the SELECTED category; reset on move.
  bool _spoilers = false;

  /// Compact: the one expanded row (-1 none) and its per-category reveals.
  int _open = -1;
  final Set<int> _openSpoilers = {};

  List<ParentsGuideCategory> get _cats => widget.guide.categories;

  @override
  void didUpdateWidget(ShowcaseGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selection, expansion and spoiler reveals are all INDEX-keyed. A new
    // guide result (the screen re-fetching for a different title, or a
    // reload) renumbers the categories, and carried-over state would reveal
    // the wrong category's spoilers.
    if (!identical(oldWidget.guide, widget.guide)) {
      // Follow LIVE focus, not a blind 0: if a card holds focus through the
      // swap, plate and SELECT must keep describing THAT card.
      final focused = widget.nodes.indexWhere((n) => n.hasFocus);
      _sel = focused >= 0 ? focused.clamp(0, _cats.length - 1) : 0;
      _spoilers = false;
      _open = -1;
      _openSpoilers.clear();
    }
  }

  void _select(int i) {
    if (_sel == i) return;
    setState(() {
      _sel = i;
      _spoilers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    if (_cats.isEmpty) return const SizedBox.shrink();
    return m.compact ? _compact(context, m) : _wide(context, m);
  }

  // ── wide: card rail + follow-focus plate ─────────────────────────────────

  Widget _wide(BuildContext context, ShowcaseMetrics m) {
    final sel = _sel.clamp(0, _cats.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SBand(
          title: 'Parents Guide',
          height: m.guideH * 1.12 + 18,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: m.gutter),
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _GuideCard(
              category: _cats[i],
              node: widget.nodes[i],
              selected: i == sel,
              onSelect: () => _select(i),
              // SELECT on the focused card: reveal/hide that category's
              // spoilers. Null when there are none, so OK stays inert.
              onOk: _spoilersOf(_cats[i]).isNotEmpty
                  ? () => setState(() => _spoilers = !_spoilers)
                  : null,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(m.gutter, 4, m.gutter, 0),
          child: _plate(context, _cats[sel]),
        ),
      ],
    );
  }

  Widget _plate(BuildContext context, ParentsGuideCategory cat) {
    final k = ShowcaseMetrics.of(context).k;
    final spoilers = _spoilersOf(cat);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      decoration: BoxDecoration(
        color: sInk.withValues(alpha: 0.055),
        border: Border.all(color: sInk.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(cat.label, style: st(11.5 * k, w: FontWeight.w700)),
              const SizedBox(width: 10),
              _SeverityMark(severity: cat.severity),
              const Spacer(),
              if (cat.totalVotes > 0)
                Text(
                  '${cat.severityVotes} of ${cat.totalVotes} rated '
                  '${cat.severity.toLowerCase()}',
                  style: st(8.5 * k, a: 0.4),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in _plainOf(cat)) _entry(item.text, 10.0 * k),
          if (_spoilers)
            for (final item in spoilers) _entry(item.text, 10.0 * k),
          if (spoilers.isNotEmpty)
            _spoilerRow(spoilers.length, _spoilers, () {
              setState(() => _spoilers = !_spoilers);
            }),
        ],
      ),
    );
  }

  Widget _entry(String text, double size) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: size * 0.55),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: sInk.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: st(size, a: 0.78).copyWith(height: 1.5)),
        ),
      ],
    ),
  );

  Widget _spoilerRow(int count, bool shown, VoidCallback onToggle) {
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '$count spoiler ${count == 1 ? 'entry' : 'entries'} '
              '${shown ? 'shown' : 'hidden'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st(compact ? 11 : 8.5 * m.k, a: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          // A pill, not a node: on DPAD the toggle is SELECT on the focused
          // card; on touch this is the tap target. The accent's one
          // appearance in the band, per the mock.
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 11 : 9 * m.k,
                vertical: compact ? 4 : 2.5 * m.k,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: sInk.withValues(alpha: 0.24)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                shown ? 'HIDE' : 'SHOW',
                style: TextStyle(
                  fontSize: compact ? 10 : 7.5 * m.k,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: widget.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── compact: accordion rows ──────────────────────────────────────────────

  Widget _compact(BuildContext context, ShowcaseMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.only(left: m.gutter, bottom: 10),
          child: Text(
            'Parents Guide',
            style: st(19, w: FontWeight.w600, a: 0.84),
          ),
        ),
        for (var i = 0; i < _cats.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(m.gutter, 0, m.gutter, 8),
            child: _accordionRow(context, i),
          ),
      ],
    );
  }

  Widget _accordionRow(BuildContext context, int i) {
    final cat = _cats[i];
    final open = _open == i;
    final spoilers = _spoilersOf(cat);
    final spoilersShown = _openSpoilers.contains(i);
    return Focus(
      focusNode: widget.nodes[i],
      onKeyEvent: (_, e) =>
          sActivate(e, () => setState(() => _open = open ? -1 : i)),
      child: GestureDetector(
        onTap: () => setState(() => _open = open ? -1 : i),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: sInk.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(cat.label, style: st(14, w: FontWeight.w600)),
                  ),
                  _SeverityMark(severity: cat.severity),
                  const SizedBox(width: 10),
                  Text(open ? '▲' : '▼', style: st(10, a: 0.4)),
                ],
              ),
              if (open) ...[
                if (cat.totalVotes > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      '${cat.severityVotes} of ${cat.totalVotes} rated '
                      '${cat.severity.toLowerCase()}',
                      style: st(10.5, a: 0.38),
                    ),
                  ),
                const SizedBox(height: 2),
                for (final item in _plainOf(cat)) _entry(item.text, 12.5),
                if (spoilersShown)
                  for (final item in spoilers) _entry(item.text, 12.5),
                if (spoilers.isNotEmpty)
                  _spoilerRow(spoilers.length, spoilersShown, () {
                    setState(() {
                      if (!_openSpoilers.add(i)) _openSpoilers.remove(i);
                    });
                  }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One wide-tier category card: title, severity mark, entry count.
class _GuideCard extends StatefulWidget {
  final ParentsGuideCategory category;
  final FocusNode node;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onOk;

  const _GuideCard({
    required this.category,
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onOk,
  });

  @override
  State<_GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<_GuideCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final cat = widget.category;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) {
          widget.onSelect();
          sKeepVisible(context);
        }
      },
      onKeyEvent: (_, e) => sActivate(e, widget.onOk),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: widget.onSelect,
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              radius: BorderRadius.circular(7 * m.k),
              child: Container(
                width: m.guideW,
                height: m.guideH,
                padding: EdgeInsets.fromLTRB(
                  11 * m.k,
                  10 * m.k,
                  11 * m.k,
                  9 * m.k,
                ),
                decoration: BoxDecoration(
                  color: sInk.withValues(alpha: widget.selected ? 0.12 : 0.07),
                  border: Border.all(
                    color: sInk.withValues(
                      alpha: widget.selected ? 0.22 : 0.09,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(7 * m.k),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        cat.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: st(10.5 * m.k, w: FontWeight.w600),
                      ),
                    ),
                    Row(
                      children: [
                        _SeverityMark(severity: cat.severity),
                        const Spacer(),
                        Text(
                          '${cat.items.length}',
                          style: st(8.5 * m.k, w: FontWeight.w600, a: 0.38),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── universe ───────────────────────────────────────────────────────────────

/// Franchise connections — a poster card with a relation eyebrow, opening the
/// related title exactly as a More Like This card does.
class ShowcaseUniverse extends StatelessWidget {
  final List<UniverseTitle> items;
  final List<FocusNode> nodes;
  final void Function(UniverseTitle)? onOpen;

  const ShowcaseUniverse({
    super.key,
    required this.items,
    required this.nodes,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final capH = m.compact ? 52.0 : 42.0 * m.k;
    return SBand(
      title: 'Universe',
      height: m.posterH * 1.10 + 24 + capH,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: m.posterGap),
        itemBuilder: (context, i) => _UniverseCard(
          item: items[i],
          node: nodes[i],
          onOpen: onOpen,
          width: m.poster,
          height: m.posterH,
        ),
      ),
    );
  }
}

class _UniverseCard extends StatefulWidget {
  final UniverseTitle item;
  final FocusNode node;
  final void Function(UniverseTitle)? onOpen;
  final double width;
  final double height;

  const _UniverseCard({
    required this.item,
    required this.node,
    required this.onOpen,
    required this.width,
    required this.height,
  });

  @override
  State<_UniverseCard> createState() => _UniverseCardState();
}

class _UniverseCardState extends State<_UniverseCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final u = widget.item;
    final slot = sSlotFill(AppThemeScope.of(context));
    final url = ViewportArtworkScope.enabledOf(context) ? u.posterUrl : null;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, e) =>
          sActivate(e, widget.onOpen == null ? null : () => widget.onOpen!(u)),
      child: SHover(
        builder: (context, hovered) => GestureDetector(
          onTap: () => widget.onOpen?.call(u),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: widget.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParallaxFocus(
                    focused: _f || hovered,
                    radius: BorderRadius.circular(7),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: widget.width,
                        height: widget.height,
                        child: (url != null && url.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                cacheManager: DebrifyImageCache.manager,
                                memCacheWidth: 300,
                                placeholder: (_, __) => ColoredBox(color: slot),
                                errorWidget: (_, __, ___) =>
                                    ColoredBox(color: slot),
                              )
                            : ColoredBox(color: slot),
                      ),
                    ),
                  ),
                  SizedBox(height: m.compact ? 8 : 7),
                  Text(
                    u.relation.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st(
                      m.compact ? 9 : 7 * m.k,
                      w: FontWeight.w700,
                      a: 0.42,
                    ).copyWith(letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    u.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st(
                      m.compact ? 12 : 10 * m.k,
                      w: FontWeight.w600,
                      a: 0.9,
                    ),
                  ),
                  if (u.yearLabel.isNotEmpty)
                    Text(
                      u.yearLabel,
                      style: st(m.compact ? 10.5 : 8.5 * m.k, a: 0.45),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── did you know ───────────────────────────────────────────────────────────

/// Trivia / goofs / quotes as reading cards — the page's footnote band.
/// Cards are focusable so the ladder can park on them (and the rail can
/// scroll), but SELECT is deliberately inert in v1: this is ambient reading,
/// like the synopsis.
class ShowcaseDidYouKnow extends StatelessWidget {
  final List<DidYouKnowEntry> entries;

  /// The full IMDb count; when it exceeds what's mounted, a terminal "+N"
  /// card says so (and carries the last focus node).
  final int total;
  final String? countLine;
  final List<FocusNode> nodes;

  const ShowcaseDidYouKnow({
    super.key,
    required this.entries,
    required this.total,
    required this.countLine,
    required this.nodes,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final hasMore = total > entries.length;
    return SBand(
      title: 'Did You Know',
      subtitle: countLine,
      height: m.dykH * 1.10 + 18,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: entries.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(width: m.compact ? 13 : 12),
        itemBuilder: (context, i) => i < entries.length
            ? _DykCard(entry: entries[i], node: nodes[i])
            : _DykMoreCard(
                count: total - entries.length,
                node: nodes[entries.length],
              ),
      ),
    );
  }
}

class _DykCard extends StatefulWidget {
  final DidYouKnowEntry entry;
  final FocusNode node;

  const _DykCard({required this.entry, required this.node});

  @override
  State<_DykCard> createState() => _DykCardState();
}

class _DykCardState extends State<_DykCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final e = widget.entry;
    final quote = e.kind == 'Quote';
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      // Basic cursor: ambient reading, SELECT is deliberately inert.
      child: SHover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => Align(
          child: ParallaxFocus(
            focused: _f || hovered,
            radius: BorderRadius.circular(7 * m.k),
            child: Container(
              width: m.dykW,
              height: m.dykH,
              padding: EdgeInsets.fromLTRB(
                m.compact ? 15 : 13 * m.k,
                m.compact ? 13 : 11 * m.k,
                m.compact ? 15 : 13 * m.k,
                m.compact ? 13 : 11 * m.k,
              ),
              decoration: BoxDecoration(
                color: sInk.withValues(alpha: _f || hovered ? 0.11 : 0.07),
                border: Border.all(color: sInk.withValues(alpha: 0.09)),
                borderRadius: BorderRadius.circular(7 * m.k),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.kind.toUpperCase(),
                    style: st(
                      m.compact ? 10 : 7.5 * m.k,
                      w: FontWeight.w700,
                      a: 0.42,
                    ).copyWith(letterSpacing: 1.2),
                  ),
                  SizedBox(height: m.compact ? 8 : 6),
                  Expanded(
                    child: Text(
                      quote ? '“${e.text}”' : e.text,
                      maxLines: m.compact ? 6 : 7,
                      overflow: TextOverflow.ellipsis,
                      style:
                          st(
                            m.compact ? 12.5 : 9.5 * m.k,
                            a: quote ? 0.88 : 0.8,
                          ).copyWith(
                            height: 1.5,
                            fontStyle: quote
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DykMoreCard extends StatefulWidget {
  final int count;
  final FocusNode node;

  const _DykMoreCard({required this.count, required this.node});

  @override
  State<_DykMoreCard> createState() => _DykMoreCardState();
}

class _DykMoreCardState extends State<_DykMoreCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      // Basic cursor: like its siblings, this card is not activatable.
      child: SHover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => Align(
          child: ParallaxFocus(
            focused: _f || hovered,
            radius: BorderRadius.circular(7 * m.k),
            child: Container(
              width: m.compact ? 110.0 : 92.0 * m.k,
              height: m.dykH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sInk.withValues(alpha: _f || hovered ? 0.11 : 0.05),
                border: Border.all(color: sInk.withValues(alpha: 0.09)),
                borderRadius: BorderRadius.circular(7 * m.k),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+${widget.count}',
                    style: st(m.compact ? 20 : 16 * m.k, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'ON IMDb',
                    style: st(
                      m.compact ? 9 : 7 * m.k,
                      w: FontWeight.w700,
                      a: 0.4,
                    ).copyWith(letterSpacing: 1.1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A band that has nothing to show yet, or could not load.
///
/// Without this a failed episode load reads as the band simply not being
/// there — indistinguishable from a movie, and with no way to retry.
class ShowcaseBandNote extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Supplied by the layout so the chip joins the band ladder. A focusable
  /// control the DPAD map does not know about is a control nobody can reach.
  final FocusNode? actionNode;

  const ShowcaseBandNote({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionNode,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 22, m.gutter, 8),
      child: Row(
        children: [
          Text(text, style: st(11.5 * m.k, a: 0.66)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            _RetryChip(label: actionLabel!, onTap: onAction!, node: actionNode),
          ],
        ],
      ),
    );
  }
}

class _RetryChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final FocusNode? node;

  const _RetryChip({required this.label, required this.onTap, this.node});

  @override
  State<_RetryChip> createState() => _RetryChipState();
}

class _RetryChipState extends State<_RetryChip> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) => sActivate(e, widget.onTap),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 22 * k,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 11 * k),
          decoration: BoxDecoration(
            color: _f ? sInk : sInk.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(11 * k),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10.5 * k,
              fontWeight: FontWeight.w600,
              color: _f ? Colors.black : sInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Details band — Creator/Country/Language/Studio/Box Office, and awards.
///
/// Reference material, not a row of verbs, so it sits at the very bottom and
/// takes no cursor. Two columns because a single column of five short pairs
/// leaves a screen mostly empty at three metres.
class ShowcaseDetails extends StatelessWidget {
  final List<(String, String)> rows;
  final String? awards;

  const ShowcaseDetails({super.key, required this.rows, required this.awards});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && (awards ?? '').isEmpty) return const SizedBox.shrink();
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 26, m.gutter, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Details', style: st(13 * m.k, w: FontWeight.w600, a: 0.84)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 46,
            runSpacing: 7,
            children: [
              for (final r in rows)
                SizedBox(
                  width: 240 * m.k,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 74 * m.k,
                        child: Text(r.$1, style: st(10 * m.k, a: 0.5)),
                      ),
                      Expanded(child: Text(r.$2, style: st(10 * m.k, a: 0.82))),
                    ],
                  ),
                ),
            ],
          ),
          if ((awards ?? '').isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(awards!, style: st(10 * m.k, a: 0.6)),
          ],
        ],
      ),
    );
  }
}
