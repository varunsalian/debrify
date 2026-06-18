import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../home/home_theme.dart';
import '../../utils/tv_keys.dart';

/// Logo-forward grid tile for an IPTV channel — mirrors the catalog grid's
/// focus/hover language (scale + gold ring/glow) but sized for channel logos
/// rather than 2:3 posters.
class IptvChannelTile extends StatefulWidget {
  final IptvChannel channel;
  final bool isTelevision;
  final FocusNode? focusNode;
  final bool isFavorited;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFavoriteToggle;

  const IptvChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.isTelevision = false,
    this.focusNode,
    this.isFavorited = false,
    this.onFavoriteToggle,
  });

  @override
  State<IptvChannelTile> createState() => _IptvChannelTileState();
}

class _IptvChannelTileState extends State<IptvChannelTile> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  // Long-press OK on TV toggles favorite; a short press still plays.
  static const _favHoldDuration = Duration(milliseconds: 500);
  Timer? _favHoldTimer;
  bool _favHoldFired = false;

  @override
  void dispose() {
    _favHoldTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final logo = ch.logoUrl;
    final isLive = ch.isLive;
    final badge = isLive
        ? 'LIVE'
        : (ch.contentType == 'vod' ? 'VOD' : null);

    // TVs are low-powered: keep the focus highlight, drop the tweening.
    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 180);

    final card = AnimatedScale(
      duration: fx,
      curve: Curves.easeOutCubic,
      scale: _active ? 1.06 : 1.0,
      child: AnimatedContainer(
        duration: fx,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _active ? 0.6 : 0.3),
              blurRadius: _active ? 32 : 12,
              offset: const Offset(0, 12),
            ),
            if (_active)
              BoxShadow(
                color: HomeTheme.focusGold.withValues(alpha: 0.5),
                blurRadius: 34,
                spreadRadius: 2,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B1B24), Color(0xFF101017)],
                  ),
                ),
              ),

              // Logo, generously inset so it never bleeds to the edges.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 34),
                child: Center(
                  child: (logo != null && logo.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: logo,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => _fallback(ch.name),
                          errorWidget: (_, __, ___) => _fallback(ch.name),
                        )
                      : _fallback(ch.name),
                ),
              ),

              // Bottom scrim + channel name.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                  child: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: _active ? 1.0 : 0.9,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),

              if (badge != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _Badge(label: badge, live: isLive),
                ),

              if (widget.onFavoriteToggle != null)
                Positioned(
                  top: 4,
                  left: 4,
                  // On TV the heart is a pure indicator — keeping it
                  // focusable makes D-pad navigation snag on it between
                  // channels. Favorite is toggled via long-press OK instead.
                  child: ExcludeFocus(
                    excluding: widget.isTelevision,
                    child: _FavButton(
                      favorited: widget.isFavorited,
                      onTap: () =>
                          widget.onFavoriteToggle!(!widget.isFavorited),
                    ),
                  ),
                ),

              if (_active)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: HomeTheme.focusGold,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        final isSelect = isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space;
        if (!isSelect) return KeyEventResult.ignored;

        // Without a favorite action (or off-TV), keep the original
        // press-to-play behaviour.
        final canHoldToFavorite =
            widget.isTelevision && widget.onFavoriteToggle != null;
        if (!canHoldToFavorite) {
          if (event is KeyDownEvent) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (event is KeyDownEvent) {
          _favHoldFired = false;
          _favHoldTimer?.cancel();
          _favHoldTimer = Timer(_favHoldDuration, () {
            if (!mounted) return;
            _favHoldFired = true;
            widget.onFavoriteToggle!(!widget.isFavorited);
          });
          return KeyEventResult.handled;
        }
        if (event is KeyUpEvent) {
          _favHoldTimer?.cancel();
          _favHoldTimer = null;
          // A long press already toggled favorite — swallow the release.
          if (!_favHoldFired) widget.onTap();
          _favHoldFired = false;
          return KeyEventResult.handled;
        }
        // Swallow auto-repeat while the key is held.
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      ),
    );
  }

  Widget _fallback(String name) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.live_tv_rounded,
            size: 30,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Number of IPTV grid columns — logo cards are landscape so we fit more
/// than the 2:3 poster grid.
int iptvGridColumnsFor(double width, {bool isTelevision = false}) {
  if (isTelevision || width >= 1500) return 6;
  if (width >= 1100) return 5;
  if (width >= 800) return 4;
  if (width >= 560) return 3;
  return 2;
}

class _Badge extends StatelessWidget {
  final String label;
  final bool live;
  const _Badge({required this.label, required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: live
            ? const Color(0xFFE50914)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _FavButton extends StatelessWidget {
  final bool favorited;
  final VoidCallback onTap;
  const _FavButton({required this.favorited, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            favorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: favorited
                ? const Color(0xFFE50914)
                : Colors.white.withValues(alpha: 0.85),
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
      ),
    );
  }
}
