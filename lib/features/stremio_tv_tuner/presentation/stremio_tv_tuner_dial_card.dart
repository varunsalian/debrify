import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_parts.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =========================================================================
// The Dial — a single surfable channel card (premium glass treatment).
// =========================================================================

class StremioTvTunerDialCard extends StatefulWidget {
  final StremioTvChannel channel;
  final Color ident;
  final FocusNode focusNode;
  final StremioTvNowPlaying? nowPlaying;
  final double displayProgress;
  final bool hideNowPlaying;
  final bool loading;

  /// TV shows a "press DOWN for options" hint on the focused card; desktop
  /// shows a "right-click" hint on hover. Distinguishes the two.
  final bool isTelevision;

  /// Touch layout: the dial's currently centred channel id — i.e. the channel
  /// the Stage above is showing. That card lights the same gold treatment
  /// D-pad focus and mouse hover light, since it means the same thing.
  ///
  /// The card subscribes itself rather than being rebuilt by an ancestor
  /// ValueListenableBuilder, so a centre change repaints the two cards whose
  /// state actually flipped instead of every mounted card in the strip — a
  /// fling across a long dial crosses a lot of cards. Null on TV / desktop,
  /// where focus and hover already drive this and the cards deliberately don't
  /// depend on the active id at all.
  final ValueListenable<String?>? centredId;

  /// Touch layout: a tap plays outright and must NOT take keyboard focus —
  /// focus would leave a second, contradictory gold ring behind on a card the
  /// Stage isn't showing, and its ensureVisible would fight the snap.
  final bool touchSelect;

  final VoidCallback onFocused;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onUp;

  const StremioTvTunerDialCard({
    super.key,
    required this.channel,
    required this.ident,
    required this.focusNode,
    required this.nowPlaying,
    required this.displayProgress,
    required this.hideNowPlaying,
    required this.loading,
    required this.isTelevision,
    required this.centredId,
    required this.touchSelect,
    required this.onFocused,
    required this.onSelect,
    required this.onLongPress,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
  });

  @override
  State<StremioTvTunerDialCard> createState() => StremioTvTunerDialCardState();
}

class StremioTvTunerDialCardState extends State<StremioTvTunerDialCard> {
  bool _focused = false;

  /// Desktop mouse hover. Mirrors DPAD focus for previewing a channel in the
  /// hero above, and lights the same gold treatment — without stealing the
  /// keyboard focus that DPAD navigation relies on.
  bool _hovered = false;

  /// Touch layout: this card is the one centred in the dial. Mirrored into
  /// state so only a real flip costs a rebuild.
  bool _centred = false;

  bool get _isCentred =>
      widget.centredId != null && widget.centredId!.value == widget.channel.id;

  @override
  void initState() {
    super.initState();
    _centred = _isCentred;
    widget.centredId?.addListener(_onCentredChanged);
  }

  void _onCentredChanged() {
    final now = _isCentred;
    if (now != _centred && mounted) setState(() => _centred = now);
  }

  @override
  void didUpdateWidget(StremioTvTunerDialCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.centredId, widget.centredId)) {
      old.centredId?.removeListener(_onCentredChanged);
      widget.centredId?.addListener(_onCentredChanged);
    }
    // A recycled card can arrive carrying a different channel, so re-derive
    // rather than trusting the mirrored flag. No setState — we're already in a
    // rebuild.
    _centred = _isCentred;
  }

  @override
  void dispose() {
    widget.centredId?.removeListener(_onCentredChanged);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        widget.onLeft();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        widget.onRight();
        return KeyEventResult.handled;
      }
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.contextMenu) {
      widget.onLongPress();
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      widget.onSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.nowPlaying?.item;
    final poster = item?.poster ?? item?.background;
    final ident = widget.ident;
    // DPAD focus, desktop hover, or (touch) sitting centred in the dial all
    // mean "this is the channel on the Stage" — one visual for all three.
    final bool active = _focused || _hovered || _centred;

    final card = Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          widget.onFocused();
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      child: GestureDetector(
        onTap: () {
          if (!widget.touchSelect) widget.focusNode.requestFocus();
          widget.onSelect();
        },
        onLongPress: widget.onLongPress,
        // Desktop: right-click opens the same quick-actions sheet as long-press.
        onSecondaryTap: widget.onLongPress,
        // Eased focus pop (matches the Home board's poster tiles) instead of
        // an instant Transform snap; the ring/bloom below stay instant, like
        // Home's shadowFx on TV, so only one property animates per move.
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: active ? 1.10 : 1.0,
          child: Container(
            width: 138,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: app.shape.brImg(16),
              // Gold focus rim + bloom, matching the Home board's poster tiles
              // (was the per-channel identity colour). Consistent focus colour
              // is what makes the two screens feel like one.
              border: Border.all(
                color: active ? app.home.focus : app.stremioTv.hairline,
                width: active ? 2.5 : 0.5,
              ),
              // The AnimatedScale pop re-rasterizes any blur shadow every frame
              // of the 140ms animation — on every DPAD move — which is what
              // janks surfing on weak TV GPUs. So on TV the focus cue is the
              // gold ring + scale only (no blurred bloom). Phone/desktop, which
              // have the GPU headroom and no rapid DPAD surfing, keep the bloom.
              boxShadow: (active && !widget.isTelevision)
                  ? [
                      BoxShadow(
                        color: app.home.focusDeep.withValues(alpha: 0.45),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 0.667,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster artwork
                  if (poster != null && !widget.hideNowPlaying)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      fadeInDuration: HomeTheme.imageFadeIn(
                        widget.isTelevision,
                      ),
                      fadeOutDuration: HomeTheme.imageFadeOut(
                        widget.isTelevision,
                      ),
                      placeholder: (_, __) => _placeholder(ident),
                      errorWidget: (_, __, ___) => _placeholder(ident),
                    )
                  // Hidden mode, TV: a 16px decode upscaled by cover-fit is
                  // the obscuring "blur" — no gaussian pass, so the card
                  // costs the same as a plain poster on the weak GPU.
                  else if (poster != null &&
                      widget.hideNowPlaying &&
                      widget.isTelevision)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 16,
                      fadeInDuration: HomeTheme.imageFadeIn(
                        widget.isTelevision,
                      ),
                      fadeOutDuration: HomeTheme.imageFadeOut(
                        widget.isTelevision,
                      ),
                      errorWidget: (_, __, ___) => _placeholder(ident),
                    )
                  else if (poster != null && widget.hideNowPlaying)
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (_, __, ___) => _placeholder(ident),
                      ),
                    )
                  else
                    _placeholder(ident),
                  // Multi-layer bottom scrim for readability.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment(0, -0.3),
                        colors: [Color(0xEE000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                  // Focused gold tint on top edge (matches the Home poster
                  // focus treatment; the CH badge below keeps its per-channel
                  // identity colour).
                  if (active)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            app.home.focus.withValues(alpha: 0.16),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  // Channel number badge.
                  Positioned(
                    top: 9,
                    left: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: ident,
                        borderRadius: app.shape.br(8),
                      ),
                      child: Text(
                        channelNumberLabel,
                        style: TextStyle(
                          color: app.core.tx,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  if (widget.channel.isFavorite)
                    Positioned(
                      top: 9,
                      right: 9,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: app.stremioTv.starAccent,
                        ),
                      ),
                    ),
                  // "How to open options" affordance — TV on the focused card
                  // (press DOWN), desktop on hover (right-click). Seated on the
                  // second row (top: 34), clear of the top-row CH badge (whose
                  // width varies with the channel number) and the favourite
                  // star. Never on touch.
                  if (widget.isTelevision && _focused)
                    const Positioned(
                      top: 34,
                      right: 9,
                      child: StremioTvTunerDialHintChip(
                        icon: Icons.keyboard_arrow_down_rounded,
                        label: 'OPTIONS',
                      ),
                    )
                  else if (!widget.isTelevision && _hovered)
                    const Positioned(
                      top: 34,
                      right: 9,
                      child: StremioTvTunerDialHintChip(
                        icon: Icons.mouse_rounded,
                        label: 'RIGHT-CLICK',
                      ),
                    ),
                  // Title + progress overlay.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(15),
                        ),
                        color: app.stremioTv.glass,
                        border: Border(
                          top: BorderSide(
                            color: app.onGlass.withValues(alpha: 0.08),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.hideNowPlaying
                                ? widget.channel.catalog.name
                                : (item?.name ?? widget.channel.catalog.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: app.onGlass,
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: app.shape.br(3),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                children: [
                                  Container(
                                    color: app.onGlass.withValues(alpha: 0.15),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: widget.displayProgress.clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: Container(
                                      // White progress fill to match Home (the
                                      // CH badge keeps the per-channel colour).
                                      decoration: BoxDecoration(
                                        color: app.onGlass.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: app.shape.br(3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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

    // MouseRegion (mouse-only — inert for touch/DPAD) makes desktop hover
    // preview the channel in the hero above, mirroring DPAD focus. It does not
    // request keyboard focus, so it can't hijack remote navigation, and does
    // not auto-scroll (only real focus does), so a passing cursor stays put.
    //
    // RepaintBoundary confines this card's repaints to itself: the focus
    // scale-pop repaints only the card you moved to (not the whole strip), and
    // the tuner's 15s broadcast tick — a bare setState on the whole subtree —
    // can't force neighbours to repaint, only cards whose progress changed.
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) {
          if (!mounted) return;
          // In the touch layout the dial's centre is the single selector: an
          // iPad trackpad hovering a card must not light a SECOND gold ring on
          // a channel the Stage isn't showing, nor pull the Stage away from the
          // centred card.
          if (widget.touchSelect) return;
          if (!_hovered) setState(() => _hovered = true);
          widget.onFocused();
        },
        // onExit can fire in a post-frame callback when the card is removed
        // while the cursor is over it (list recycling on scroll), so guard
        // mounted.
        onExit: (_) {
          if (mounted && _hovered) setState(() => _hovered = false);
        },
        child: card,
      ),
    );
  }

  String get channelNumberLabel =>
      'CH ${widget.channel.channelNumber.toString().padLeft(2, '0')}';

  Widget _placeholder(Color ident) {
    final app = AppThemeScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ident.withValues(alpha: 0.25),
            const Color(0xFF0A0A12),
            ident.withValues(alpha: 0.08),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: Icon(
          widget.channel.type == 'series'
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          color: app.core.tx.withValues(alpha: 0.18),
          size: 32,
        ),
      ),
    );
  }
}
