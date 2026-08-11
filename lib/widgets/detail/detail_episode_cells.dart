import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debrify_image_cache.dart';
import '../../services/trakt/trakt_episode_model.dart';
import '../../theme/widgets/themed_artwork.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../home/home_theme.dart';
import 'detail_style.dart';
import 'theme/detail_theme.dart';

/// How a cell reaches the per-episode options menu.
///
/// `_CompactEpisodeRow` can bind RIGHT because it lives in a vertical,
/// right-most pane. A horizontal rail or a grid needs RIGHT to advance, so
/// those bind a **held OK** instead — which is a real key implementation, not
/// `GestureDetector.onLongPress` (a held DPAD SELECT never becomes a pointer
/// long-press).
enum DetailOptionsGesture { rightArrow, holdOk }

/// Focus, activation and options handling shared by every episode cell.
///
/// Presentational cells wrap themselves in one of these; none of them
/// re-implement the key handling.
class DetailEpisodeInteraction extends StatefulWidget {
  final FocusNode focusNode;
  final DetailOptionsGesture gesture;
  final VoidCallback onPlay;
  final VoidCallback onOptions;

  /// LEFT at this cell (vertical lists cross panes with it).
  final VoidCallback? onLeftEdge;

  /// Scrolls the cell into view when focused. Off for cells inside a viewport
  /// the layout scrolls itself.
  final bool ensureVisible;
  final double ensureVisibleAlignment;
  final Axis ensureVisibleAxis;

  final void Function(bool focused)? onFocusChange;
  final Widget Function(BuildContext, bool focused) builder;

  const DetailEpisodeInteraction({
    super.key,
    required this.focusNode,
    required this.gesture,
    required this.onPlay,
    required this.onOptions,
    required this.builder,
    this.onLeftEdge,
    this.ensureVisible = true,
    this.ensureVisibleAlignment = 0.5,
    this.ensureVisibleAxis = Axis.vertical,
    this.onFocusChange,
  });

  @override
  State<DetailEpisodeInteraction> createState() =>
      _DetailEpisodeInteractionState();
}

class _DetailEpisodeInteractionState extends State<DetailEpisodeInteraction> {
  bool _focused = false;

  /// Pointer hover, feeding the SAME visual the DPAD cursor gets — the lift
  /// and the caption plate — so mousing across the rail reads like walking
  /// it with a remote. Purely visual: hover must not request focus (that
  /// would fire [DetailEpisodeInteraction.onFocusChange] and the
  /// ensure-visible scroll, letting the mouse yank the rail around) and it
  /// is never reported upward.
  bool _hovered = false;
  Timer? _holdTimer;
  bool _holdFired = false;
  bool _keyDownSeen = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _resetHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdFired = false;
    _keyDownSeen = false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _resetHold();
        widget.onFocusChange?.call(f);
        if (f && widget.ensureVisible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !context.mounted) return;
            // The NEAREST scrollable only — the rail this cell lives in.
            // `Scrollable.ensureVisible` scrolls every ancestor, so episode
            // focus was also moving the page's vertical list behind the band
            // ladder's back. `ensureVisibleAxis` was declared for exactly this
            // and never honoured.
            final rail = Scrollable.maybeOf(context);
            final box = context.findRenderObject();
            if (rail == null || box is! RenderBox || !box.attached) return;
            rail.position.ensureVisible(
              box,
              alignment: widget.ensureVisibleAlignment,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // Snap on TV: a held key retargets an in-flight glide every
              // repeat, which reads as the cursor trailing the press.
              duration: PlatformUtil.isAndroidTvCached
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        final k = event.logicalKey;

        // Activation — plain press plays, held press opens options.
        if (isActivateOrSpaceKey(k)) {
          if (widget.gesture == DetailOptionsGesture.holdOk) {
            if (event is KeyDownEvent) {
              _keyDownSeen = true;
              _holdFired = false;
              _holdTimer?.cancel();
              _holdTimer = Timer(const Duration(milliseconds: 800), () {
                _holdFired = true;
                HapticFeedback.mediumImpact();
                widget.onOptions();
              });
              return KeyEventResult.handled;
            }
            if (event is KeyUpEvent) {
              _holdTimer?.cancel();
              // A key-up with no matching key-down belongs to whatever had
              // focus before — never treat it as a tap here.
              if (!_keyDownSeen) return KeyEventResult.handled;
              if (!_holdFired) widget.onPlay();
              _resetHold();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) {
            widget.onPlay();
            return KeyEventResult.handled;
          }
          return event is KeyUpEvent
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }

        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (widget.gesture == DetailOptionsGesture.rightArrow &&
            k == LogicalKeyboardKey.arrowRight) {
          widget.onOptions();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowLeft && widget.onLeftEdge != null) {
          widget.onLeftEdge!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            widget.onOptions();
          },
          behavior: HitTestBehavior.opaque,
          // Isolate the repaint: focus flips a ring and an overlay, and without
          // a boundary every DPAD move repaints the whole rail's layer.
          child: RepaintBoundary(
            child: widget.builder(context, _focused || _hovered),
          ),
        ),
      ),
    );
  }
}

/// Episode still with the watched veil, progress bar and UP NEXT badge.
///
/// The watched state is expressed ONCE — the dimming veil plus a single tick.
/// (Classic renders a tick on the thumbnail *and* another in the trailing
/// column; that duplication is not carried over here.)
class DetailEpisodeThumb extends StatelessWidget {
  final TraktEpisode episode;
  final String? fallbackImage;
  final double? progress; // 0..100
  final bool isNext;

  /// This site's own corner radius, before the theme's image scale.
  ///
  /// A scalar rather than a [BorderRadius] because [ThemedArtwork] owns the
  /// framing now and applies that scale itself; every caller was passing a
  /// uniform radius anyway.
  final double radius;

  final bool showTick;

  const DetailEpisodeThumb({
    super.key,
    required this.episode,
    required this.fallbackImage,
    required this.progress,
    required this.isNext,
    this.radius = 7,
    this.showTick = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final p = progress ?? 0;
    final watched = p >= 100;
    final partial = p > 0 && p < 100;
    final url = episode.thumbnailUrl ?? fallbackImage;
    // The frame is the artwork's, so it belongs to [ThemedArtwork] — and the
    // veil, tick, badge and progress bar stay inside that one clip, exactly as
    // they sat inside the one this replaces.
    return ThemedArtwork(
      role: ArtRole.still,
      radius: radius,
      // Every layout that hosts a thumb builds its cells lazily — Marquee's
      // and Console's rails, the three vertical episode lists.
      inList: true,
      builder: (context, blend) => Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              color: blend?.$1,
              colorBlendMode: blend?.$2,
              cacheManager: DebrifyImageCache.manager,
              // Rail/grid thumbs are ~200 logical px at most; never decode a
              // full-size poster fallback for one.
              memCacheWidth: 400,
              fadeInDuration: HomeTheme.imageFadeIn(
                PlatformUtil.isAndroidTvCached,
              ),
              fadeOutDuration: HomeTheme.imageFadeOut(
                PlatformUtil.isAndroidTvCached,
              ),
              placeholder: (_, __) => ColoredBox(color: t.placeholder),
              errorWidget: (_, __, ___) => ColoredBox(color: t.placeholder),
            )
          else
            ColoredBox(color: t.placeholder),
        ],
      ),
      // Everything above is the still; everything below is chrome ON it. The
      // frame is a treatment of the IMAGE — a `faded` look must not dissolve
      // the progress bar at the bottom of the cell, and a `matted` one must
      // not shrink the UP NEXT flag into the mount.
      overlay: Stack(
        fit: StackFit.expand,
        children: [
          if (watched) ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          if (watched && showTick)
            Center(
              child: Icon(
                Icons.check_circle_rounded,
                // STATE: a measurement, not a flag.
                color: t.state,
                size: 22,
              ),
            ),
          if (isNext && !watched)
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  // CALLOUT: an attention flag, not a measurement.
                  color: t.callout,
                  borderRadius: t.brSm,
                ),
                child: Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: t.calloutText,
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
                color: Colors.black.withValues(alpha: 0.55),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (p / 100).clamp(0.0, 1.0),
                  // The one place a theme may carry a gradient — small type
                  // never does, or it becomes unreadable.
                  child: t.stateGradient != null
                      ? DecoratedBox(
                          decoration: BoxDecoration(gradient: t.stateGradient),
                        )
                      : ColoredBox(color: t.state),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wide 16:9 card with a caption below — Marquee's rail, Console's grid.
class DetailEpisodeCard extends StatelessWidget {
  final TraktEpisode episode;
  final String? fallbackImage;
  final double? progress;
  final bool isNext;
  final FocusNode focusNode;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final double width;
  final void Function(bool)? onFocusChange;
  final Axis scrollAxis;

  /// Exact height reserved for the caption band.
  ///
  /// The rail that hosts these cards has to be a bounded height, and it derives
  /// that from `art + gap + captionHeight`. If the caption is then free to grow
  /// — a taller data font, a bigger text scale — the card overflows the rail it
  /// was measured for. Reserving the band makes the two agree by construction
  /// instead of by estimate.
  final double captionHeight;

  const DetailEpisodeCard({
    super.key,
    required this.episode,
    required this.fallbackImage,
    required this.progress,
    required this.isNext,
    required this.focusNode,
    required this.onPlay,
    required this.onOptions,
    required this.width,
    required this.captionHeight,
    this.onFocusChange,
    this.scrollAxis = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return DetailEpisodeInteraction(
      focusNode: focusNode,
      // Horizontal cells need RIGHT to advance.
      gesture: DetailOptionsGesture.holdOk,
      onPlay: onPlay,
      onOptions: onOptions,
      onFocusChange: onFocusChange,
      ensureVisibleAxis: scrollAxis,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DetailFocusRing(
              focused: focused,
              radius: t.brImg,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DetailEpisodeThumb(
                  episode: episode,
                  fallbackImage: fallbackImage,
                  progress: progress,
                  isNext: isNext,
                  // 8 is the base the detail themes scale their image radius
                  // from, so this resolves to the `t.brImg` the ring above is
                  // drawn at. Handing over `t.brImg` itself would scale an
                  // already-scaled number twice.
                  radius: 8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: captionHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${episode.number}',
                    style: t.dataStyle(size: 11, weight: FontWeight.w800),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: focused ? t.tx : t.tx2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumb · number+title · meta · state — the vertical-list cell.
class DetailEpisodeRow extends StatelessWidget {
  final TraktEpisode episode;
  final String? fallbackImage;
  final double? progress;
  final bool isNext;
  final FocusNode focusNode;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final VoidCallback? onLeftEdge;
  final double thumbWidth;
  final bool showSynopsis;

  const DetailEpisodeRow({
    super.key,
    required this.episode,
    required this.fallbackImage,
    required this.progress,
    required this.isNext,
    required this.focusNode,
    required this.onPlay,
    required this.onOptions,
    this.onLeftEdge,
    this.thumbWidth = 104,
    this.showSynopsis = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final p = progress ?? 0;
    final watched = p >= 100;
    final partial = p > 0 && p < 100;
    return DetailEpisodeInteraction(
      focusNode: focusNode,
      // Vertical, right-most list — RIGHT is free for options, as in Classic.
      gesture: DetailOptionsGesture.rightArrow,
      onPlay: onPlay,
      onOptions: onOptions,
      onLeftEdge: onLeftEdge,
      builder: (context, focused) => DetailFocusRing(
        focused: focused,
        radius: t.brRadius,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: focused ? t.panel : null,
            borderRadius: t.brRadius,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: thumbWidth,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DetailEpisodeThumb(
                    episode: episode,
                    fallbackImage: fallbackImage,
                    progress: progress,
                    isNext: isNext,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${episode.number}. ${episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.tx,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _MetaLine(episode: episode),
                    if (showSynopsis && (episode.overview?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          episode.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyStyle(size: 11.5, height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (watched)
                Icon(Icons.check_circle_rounded, color: t.state, size: 17)
              else if (partial)
                Text(
                  '${p.round()}%',
                  style: t.dataStyle(
                    size: 11.5,
                    color: t.state,
                    weight: FontWeight.w700,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: focused ? t.tx2 : t.tx3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final TraktEpisode episode;
  const _MetaLine({required this.episode});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final bits = <Widget>[];
    final r = episode.rating;
    if (r != null && r > 0) {
      bits.add(
        Text(
          '★ ${r.toStringAsFixed(1)}',
          // RATING, not state: this is data. Signal keeps IMDb yellow, which
          // is deliberately NOT the state gold.
          style: t.dataStyle(
            size: 11,
            color: t.rating,
            weight: FontWeight.w700,
          ),
        ),
      );
    }
    final aired = episode.formattedAirDate;
    if (aired != null && aired.isNotEmpty) {
      bits.add(Text(aired, style: t.dataStyle(size: 11)));
    }
    if (bits.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: bits,
    );
  }
}

/// Loading / failure for the collection region.
///
/// One implementation so every layout has the same focus contract. Retry does
/// NOT autofocus: entry focus belongs to the page's primary action, and each
/// layout's DOWN edge already routes into this region, so grabbing it here
/// would either be discarded or would yank the cursor off Play.
///
/// Never used for *missing movie metadata* — that is not an error, and those
/// regions are simply omitted.
class DetailEpisodesStatus extends StatelessWidget {
  final bool loading;
  final VoidCallback onRetry;
  final VoidCallback? onSearchForSources;

  /// Kept for callers; the status widget itself no longer varies by platform
  /// now that Retry does not autofocus.
  // ignore: unused_field
  final bool isTelevision;
  final FocusNode? retryNode;
  final VoidCallback? onUpEdge;

  const DetailEpisodesStatus({
    super.key,
    required this.loading,
    required this.onRetry,
    required this.onSearchForSources,
    required this.isTelevision,
    this.retryNode,
    this.onUpEdge,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    final t = DetailThemeScope.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            onUpEdge != null) {
          onUpEdge!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tv_off_rounded, size: 40, color: t.tx3),
              const SizedBox(height: 12),
              Text(
                "Couldn't load episodes",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.tx,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The episode list is unavailable right now.',
                textAlign: TextAlign.center,
                style: t.bodyStyle(size: 12.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    focusNode: retryNode,
                    style: ButtonStyle(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? BorderSide(
                                color: t.focus,
                                width: t.focusWidthFor(isTelevision),
                              )
                            : null,
                      ),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                  if (onSearchForSources != null)
                    OutlinedButton.icon(
                      style: ButtonStyle(
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? BorderSide(
                                  color: t.focus,
                                  width: t.focusWidthFor(
                                    PlatformUtil.isAndroidTvCached,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      onPressed: onSearchForSources,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Search for sources'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
