import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/home/card_focus_rise.dart';
import '../../../widgets/home/home_theme.dart';
import 'home_card_style.dart';

/// Stremio-shaped artwork card for a favourite that has a real image (a Stremio
/// TV channel's now-playing poster, or an IPTV channel's logo). Shows the image
/// over a purple gradient — with a live-TV glyph fallback when it's missing or
/// fails to load — and the title below, matching the catalog card's size, corner
/// radius, hover/focus lift and selection ring so the row reads as one board.
class HomeArtPoster extends StatefulWidget {
  final String? imageUrl;
  final String title;
  final bool showTitle;

  /// How the image fills the 2:3 tile — cover for posters, contain for logos.
  final BoxFit imageFit;

  /// Optional top-left badge text (e.g. a channel number) drawn over the tile.
  final String? badge;

  /// When true, a red "LIVE" pill is drawn top-right — signalling that this is a
  /// channel and the artwork is what's playing on it right now.
  final bool live;

  /// Optional resume-progress fraction (0..1). When set, a thin progress bar is
  /// drawn along the bottom edge of the poster (used by the Playlist row).
  final double? progress;
  final bool isTelevision;

  /// Focus ring override (Canvas favourites cells pass white); null keeps
  /// the classic violet-on-TV grammar.
  final Color? ringColor;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  /// Fired when this card gains DPAD focus (TV only — see [_HomeArtPosterState]'s
  /// `onFocusChange`). The IPTV favourites rows use it to retune the hero's
  /// video region (boxed on classic, full-bleed on Canvas) to the focused
  /// channel's live stream; other favourites rows pass a clearing/stage
  /// callback so a live feed never lingers when focus moves off IPTV without
  /// passing through a catalog/CW card first.
  final VoidCallback? onFocused;

  const HomeArtPoster({
    super.key,
    required this.imageUrl,
    required this.title,
    this.showTitle = true,
    required this.isTelevision,
    required this.focusNode,
    required this.onOpen,
    this.imageFit = BoxFit.cover,
    this.badge,
    this.live = false,
    this.progress,
    this.ringColor,
    this.onFocused,
  });

  @override
  State<HomeArtPoster> createState() => _HomeArtPosterState();
}

class _HomeArtPosterState extends State<HomeArtPoster> {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  Widget _glyph() {
    final app = AppThemeScope.of(context);
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 40,
        color: app.fade(app.home.chromeAccent, _active ? 1 : 0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final url = widget.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final posterCard = CardFocusRise(
      active: _active,
      isTelevision: widget.isTelevision,
      ringColor: widget.ringColor,
      children: [
        // Base gradient — the fallback backdrop and the ground behind
        // any letterboxed (contain-fit) logo.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1D5C), Color(0xFF1A1440), Color(0xFF0D0B1A)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (hasImage)
          Padding(
            padding: widget.imageFit == BoxFit.contain
                ? const EdgeInsets.all(12)
                : EdgeInsets.zero,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: widget.imageFit,
              memCacheWidth: widget.isTelevision ? 320 : 480,
              // Short fade on TV (see HomeTheme.imageFadeIn) — cached loads
              // land settled with no fade.
              fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
              fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
              placeholder: (_, __) => _glyph(),
              errorWidget: (_, __, ___) => _glyph(),
            ),
          )
        else
          _glyph(),
        // Optional channel-number badge, top-left.
        if (widget.badge != null)
          Positioned(
            top: 10,
            left: 10,
            child: Text(
              widget.badge!,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        // "LIVE" pill, top-right — marks this as a channel currently
        // playing the shown artwork.
        if (widget.live)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: app.shape.br(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: homeCardProgressRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Resume-progress bar along the bottom edge (Playlist row).
        if (widget.progress != null && widget.progress! > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.progress!,
                    child: Container(color: homeCardProgressRed),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _keyDown = false;
        if (f) {
          widget.onFocused?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV glides too (was a hard jump): repeated
              // DPAD moves retarget the in-flight scroll, so held browsing
              // stays one continuous motion. Short on purpose; 200ms trailed
              // the keypress on-device.
              duration: widget.isTelevision
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterCard,
              if (widget.showTitle) ...[
                const SizedBox(height: HomeArtCaption.gap),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: HomeArtCaption.maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _active ? app.core.tx : app.fade(app.core.tx, 0.92),
                    fontSize: HomeArtCaption.fontSize,
                    fontWeight: FontWeight.w600,
                    height: HomeArtCaption.lineHeight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
