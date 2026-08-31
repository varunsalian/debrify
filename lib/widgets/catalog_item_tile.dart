import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../theme/app_theme_scope.dart';
import '../theme/widgets/themed_artwork.dart';
import '../utils/platform_util.dart';
import '../utils/tv_keys.dart';
import 'home/card_focus_rise.dart';
import 'home/home_theme.dart';
import 'movie_watched_badge.dart';

/// Poster-first grid tile for catalog and search results.
///
/// Tap (or D-pad SELECT) calls [onOpen]. A long-press calls [onLongPress]
/// (used to Quick Play straight from the grid). Description, year, genres
/// and per-item actions live on the detail screen — the grid stays clean.
class CatalogItemTile extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode? focusNode;
  final bool hasBoundSource;
  final VoidCallback onOpen;

  /// Optional long-press action (Quick Play). When null, long-press is a no-op.
  final VoidCallback? onLongPress;

  /// Fires when this tile *gains* DPAD/hover focus — the hook the Discover
  /// two-pane detail rail uses to know which item to preview. Not called on
  /// blur (the rail keeps showing the last-focused title, Plex-style).
  final VoidCallback? onFocused;

  /// Optional watch progress (0..1). When > 0 a slim bar is pinned to the
  /// bottom of the poster — used by the Trakt "continue watching" grid.
  final double? progress;

  /// When true (default) the title + year fade in over the poster on focus.
  /// Set false when the caller renders a persistent title below the poster
  /// (the See-All grid), so the two don't stack.
  final bool showInlineTitle;

  /// When false the MOVIE/SERIES glass badge is dropped. Discover resolves
  /// this from its poster-card setting; other mixed-type grids leave it on for
  /// at-a-glance identification.
  final bool showTypeBadge;

  /// When false the ★-rating chip is dropped. Discover resolves this from its
  /// poster-card setting.
  final bool showRatingBadge;

  /// Stack poster badges down the left edge instead of spreading them across
  /// the top. The Discover stage shelf uses this on its narrow 2:3 cards, where
  /// the type, rating and watched marker cannot safely share one row.
  final bool compactBadgeLayout;

  /// Wear the HOME BOARD's card grammar instead of this tile's own: the shared
  /// [CardFocusRise] (calm 1.045 lift, twin shadow, ring — all on one curve),
  /// the board's short poster fade, and a 140ms scroll GLIDE on TV instead of
  /// a hard jump, which the board calls the single biggest "not native" tell.
  ///
  /// Set by the Discover STAGE shelf, which sits on a full-bleed stage beside
  /// the Home board and has to move like it. Every other caller keeps this
  /// tile's existing gold-rim grammar, untouched.
  final bool boardChrome;

  const CatalogItemTile({
    super.key,
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.hasBoundSource,
    required this.onOpen,
    this.onLongPress,
    this.onFocused,
    this.progress,
    this.showInlineTitle = true,
    this.showTypeBadge = true,
    this.showRatingBadge = true,
    this.compactBadgeLayout = false,
    this.boardChrome = false,
  });

  @override
  State<CatalogItemTile> createState() => _CatalogItemTileState();
}

class _CatalogItemTileState extends State<CatalogItemTile> {
  bool _focused = false;
  bool _hovered = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _keyDownReceived = false;

  bool get _active => _focused || _hovered;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.item;
    final poster = item.poster;
    final rating = item.imdbRating;
    final typeLabel = item.type == 'series' ? 'SERIES' : 'MOVIE';
    final isMovie = item.type.toLowerCase() == 'movie';
    final supportsWatched = isMovie || item.type.toLowerCase() == 'series';
    final movieId = item.effectiveImdbId ?? item.id;
    final board = widget.boardChrome;
    // TVs are low-powered: keep the focus highlight but make it instant
    // (no per-frame tweening of large posters/shadows). Board chrome animates
    // instead — [CardFocusRise] is shaped to be cheap enough for it.
    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 180);

    // The POSTER, and nothing else. Split from [chrome] because
    // `ThemedArtwork`'s frame is a treatment of the image: handing it the
    // whole stack made a `faded` look dissolve the progress bar and the
    // badges along with the artwork, and a `matted` one shrink them into
    // the mount.
    //
    // A function of the theme's grade rather than a plain list, because the
    // blend has to reach the image constructor itself: compositing inside the
    // image's own paint is what makes grading affordable in a grid at all,
    // where a filter layer per poster would not be.
    List<Widget> artwork((Color, BlendMode)? blend) => <Widget>[
      if (poster != null && poster.isNotEmpty)
        CachedNetworkImage(
          imageUrl: poster,
          fit: BoxFit.cover,
          color: blend?.$1,
          colorBlendMode: blend?.$2,
          // Decode posters at a capped width instead of full source
          // resolution (~780px → ~3.6MB each). Tiles never exceed ~320px
          // wide, so this roughly thirds the decoded bytes per poster —
          // the biggest memory win for the catalog grid on low-RAM TVs.
          memCacheWidth: widget.isTelevision ? 320 : 480,
          // TV, classic chrome: no per-image crossfade — a saveLayer per
          // poster janks the weak GPU when a whole grid fills in at once
          // (matches the board's _ArtPoster path). Board chrome takes the
          // board's short fade instead: one shelf of cards is a far smaller
          // burst than a grid, and posters snapping in as hard rectangles is
          // the last cheap tell at the card level.
          fadeInDuration: board
              ? HomeTheme.imageFadeIn(widget.isTelevision)
              : (widget.isTelevision
                    ? Duration.zero
                    : const Duration(milliseconds: 250)),
          fadeOutDuration: board
              ? HomeTheme.imageFadeOut(widget.isTelevision)
              : (widget.isTelevision
                    ? Duration.zero
                    : const Duration(milliseconds: 100)),
          placeholder: (_, __) => _placeholder(item.name),
          errorWidget: (_, __, ___) => _placeholder(item.name),
        )
      else
        _placeholder(item.name),
    ];

    // Everything painted ON the poster: the focus wash, the badges, the
    // inline title and the progress bar. Never framed, never graded.
    List<Widget> chrome() => <Widget>[
      // Bottom gradient — only when focused — for the inline title. Board
      // chrome skips it: board cards carry no focus wash, and on a stage the
      // focused title is named at full size below the shelf anyway.
      if (_active && !board)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                  stops: const [0.0, 0.55, 0.85, 1.0],
                ),
              ),
            ),
          ),
        ),

      if (widget.compactBadgeLayout)
        Positioned(
          top: 10,
          left: 10,
          child: Column(
            key: const ValueKey('catalog-compact-badges'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showTypeBadge) _GlassChip(label: typeLabel),
              if (rating != null && widget.showRatingBadge)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _RatingChip(value: rating),
                ),
              if (supportsWatched)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: MovieWatchedBadge(
                    imdbId: movieId,
                    contentType: item.type,
                    compact: true,
                    tickPolicyScoped: true,
                  ),
                ),
            ],
          ),
        )
      else ...[
        if (widget.showTypeBadge)
          Positioned(top: 10, left: 10, child: _GlassChip(label: typeLabel)),
        if (supportsWatched)
          Positioned(
            top: 9,
            left: widget.showTypeBadge ? 68 : 9,
            child: MovieWatchedBadge(
              imdbId: movieId,
              contentType: item.type,
              tickPolicyScoped: true,
            ),
          ),
        if (rating != null && widget.showRatingBadge)
          Positioned(top: 10, right: 10, child: _RatingChip(value: rating)),
      ],

      if (widget.hasBoundSource)
        Positioned(
          bottom: 10,
          right: 10,
          child: Icon(
            Icons.bookmark_rounded,
            size: 18,
            color: app.core.tx,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),

      // Focused title overlay — appears inside the poster on focus so the
      // chrome below the tile stays calm. Suppressed when the caller shows a
      // persistent title below the poster.
      if (_active && widget.showInlineTitle)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.15,
                  ),
                ),
                if (item.year != null && item.year!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.year!,
                      style: TextStyle(
                        color: app.fade(app.core.tx, 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

      // Continue-watching progress bar, pinned to the poster bottom.
      if (widget.progress != null && widget.progress! > 0)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: _ProgressBar(value: widget.progress!.clamp(0.0, 1.0)),
          ),
        ),
    ];

    // Board chrome re-hosts those very same layers in the board's rise; the
    // classic scale/shadow/clip below simply isn't built.
    final Widget card;
    if (board) {
      card = CardFocusRise(
        active: _active,
        isTelevision: widget.isTelevision,
        // White ring, like the Canvas board's cells — the violet stays with
        // classic chrome.
        ringColor: Colors.white,
        // One child, not the layers spread straight in: the artwork's framing
        // and grade belong together, so the whole card face goes through
        // [ThemedArtwork]. [CardFocusRise] still owns the outer clip at the
        // same radius, so under a bleeding frame the board card keeps its
        // corners — that clip is the board's card shape, not the art's.
        children: [
          ThemedArtwork(
            role: ArtRole.poster,
            radius: 10,
            inList: true,
            builder: (context, blend) =>
                Stack(fit: StackFit.expand, children: artwork(blend)),
            overlay: Stack(fit: StackFit.expand, children: chrome()),
          ),
        ],
      );
    } else {
      card = AnimatedScale(
        duration: fx,
        curve: Curves.easeOutCubic,
        scale: _active ? 1.08 : 1.0,
        child: AnimatedContainer(
          duration: fx,
          decoration: BoxDecoration(
            borderRadius: app.shape.br(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _active ? 0.7 : 0.35),
                blurRadius: _active ? (widget.isTelevision ? 20 : 38) : 14,
                offset: const Offset(0, 14),
              ),
              if (_active) ...[
                // Tight bright gold rim.
                BoxShadow(
                  color: app.fade(app.home.focus, 0.6),
                  blurRadius: 30,
                  spreadRadius: 1,
                ),
                // Wide warm amber bloom for the cinematic falloff. Skipped on
                // TV: a blur-90 soft shadow repainted on every D-pad focus move
                // is the main scroll-jank source on weak TV GPUs.
                if (!widget.isTelevision)
                  BoxShadow(
                    color: app.fade(app.home.focusDeep, 0.32),
                    blurRadius: 90,
                    spreadRadius: 10,
                  ),
              ],
            ],
          ),
          // The framing is the artwork's, so [ThemedArtwork] owns it outright
          // — everything drawn over the poster (the wash, the chips, the
          // progress bar, the ring) lives inside that one clip rather than
          // under a second one of our own.
          child: ThemedArtwork(
            role: ArtRole.poster,
            radius: 14,
            inList: true,
            builder: (context, blend) => Stack(
              fit: StackFit.expand,
              children: artwork(blend),
            ),
            // Chrome and the focus ring together: badges, the inline title,
            // the progress bar and the cursor are all things painted ON the
            // poster, so none of them may be dissolved by a `faded` look or
            // shrunk into a `matted` one.
            overlay: Stack(
              fit: StackFit.expand,
              children: [
                ...chrome(),
                if (_active)
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: app.shape.br(14),
                        border: Border.all(
                          color: app.home.focus,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) {
          _longPressTimer?.cancel();
          _longPressTriggered = false;
          _keyDownReceived = false;
        }
        if (f) {
          widget.onFocused?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV, board chrome: GLIDE (140ms) rather than jump — a held
              // DPAD repeat retargets the in-flight scroll from the current
              // offset, and a short glide converges fast enough that the
              // motion never reads as trailing the keypress. Classic chrome
              // keeps the instant jump its grids were tuned around.
              //
              // Android TV snaps EVERYWHERE, board chrome included: even the
              // short glide is a scrolled repaint on every frame of every
              // step, and after the Spotlight board switched to the snap a
              // MiBox reported Discover — whose stage shelves ride this exact
              // path — as the one place navigation still dragged. Apple TV
              // keeps the glide.
              duration: widget.isTelevision
                  ? (board && !PlatformUtil.isAndroidTvCached
                      ? const Duration(milliseconds: 140)
                      : Duration.zero)
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDownReceived = true;
            _longPressTriggered = false;
            _longPressTimer?.cancel();
            if (widget.onLongPress != null) {
              _longPressTimer = Timer(const Duration(milliseconds: 800), () {
                _longPressTriggered = true;
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              });
            }
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _longPressTimer?.cancel();
            if (!_keyDownReceived) return KeyEventResult.handled;
            if (!_longPressTriggered) {
              widget.onOpen();
            }
            _longPressTriggered = false;
            _keyDownReceived = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  widget.onLongPress!();
                },
          behavior: HitTestBehavior.opaque,
          // Isolate the tile's repaint: focus flips its shadow/ring/overlay,
          // and without a boundary each DPAD move repaints the whole grid
          // viewport layer instead of just the two affected tiles.
          child: RepaintBoundary(child: card),
        ),
      ),
    );
  }

  Widget _placeholder(String title) {
    final app = AppThemeScope.of(context);
    return Container(
      color: app.home.posterPlaceholder,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: app.fade(app.core.tx, 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Number of grid columns for a given width. Fewer columns = bigger posters
/// = a more premium feel. TV tops out at 5.
int catalogGridColumnsFor(double width, {bool isTelevision = false}) {
  if (isTelevision || width >= 1500) return 5;
  if (width >= 1100) return 4;
  if (width >= 700) return 3;
  return 2;
}

class _GlassChip extends StatelessWidget {
  final String label;
  const _GlassChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: app.shape.br(6),
        border: Border.all(
          // On the glass, not the page — see AppTheme.onGlass.
          color: app.fade(app.onGlass, 0.18),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: app.fade(app.core.tx, 0.9),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Slim "continue watching" progress bar (Netflix-style red fill).
class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: const ColoredBox(color: Color(0xFFE50914)),
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  final double value;
  const _RatingChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: app.shape.br(6),
        border: Border.all(
          // On the glass, not the page — see AppTheme.onGlass.
          color: app.fade(app.onGlass, 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFACC15)),
          const SizedBox(width: 3),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: app.core.tx,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
