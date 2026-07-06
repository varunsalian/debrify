import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../browse/brand_accent.dart';
import '../home/home_theme.dart';
import '../../utils/tv_keys.dart';

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)".
final RegExp _resExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

const Color _liveDot = Color(0xFF34D399); // emerald — a calm "on air" cue

/// Compact guide-style list row for an IPTV channel: a small logo chip, the
/// channel name, and a "category • resolution" sub-line. Scales far better than
/// a logo grid for very large channel lists, and keeps the app's gold focus
/// language for DPAD.
class IptvChannelRow extends StatefulWidget {
  final IptvChannel channel;
  final bool isTelevision;
  final FocusNode? focusNode;
  final bool isFavorited;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFavoriteToggle;

  const IptvChannelRow({
    super.key,
    required this.channel,
    required this.onTap,
    this.isTelevision = false,
    this.focusNode,
    this.isFavorited = false,
    this.onFavoriteToggle,
  });

  @override
  State<IptvChannelRow> createState() => _IptvChannelRowState();
}

class _IptvChannelRowState extends State<IptvChannelRow>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  /// Touch phones/tablets have no hover, so the favourite affordance can't hide
  /// behind one — keep it visible there. Desktop reveals it on hover, TV on
  /// focus; Android TV reports as android but is flagged via [isTelevision].
  bool get _isTouchMobile =>
      !widget.isTelevision &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // Long-press OK on TV toggles favorite; a short press still plays. The hold
  // is driven by a controller so the focused row can show a filling heart —
  // making the otherwise-invisible gesture discoverable.
  static const _favHoldDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _favHoldDuration,
  );
  bool _favHoldFired = false;

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _favHoldFired = true;
        widget.onFavoriteToggle?.call(!widget.isFavorited);
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isLive = ch.isLive;
    final brand = brandAccentFor(ch.name);

    // Pull the resolution out of the name into the sub-line; show a clean name.
    final resMatch = _resExp.firstMatch(ch.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? ch.name
        : ch.name
            .replaceRange(resMatch.start, resMatch.end, '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final group = ch.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];
    final sub = subParts.isNotEmpty
        ? subParts.join('  •  ')
        : (isLive ? 'Live' : '');

    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 150);

    final row = AnimatedContainer(
      duration: fx,
      // Constant 2px border (transparent at rest) so focus never shifts layout.
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _active ? const Color(0xFF141824) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _active ? HomeTheme.focusGold : Colors.transparent,
          width: 2,
        ),
        boxShadow: _active
            ? [
                BoxShadow(
                  color: HomeTheme.focusGold.withValues(alpha: 0.28),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          _LogoChip(logoUrl: ch.logoUrl, name: displayName, brand: brand),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLive) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _liveDot,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _liveDot.withValues(alpha: 0.6),
                              blurRadius: 7,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: _active ? 1.0 : 0.94,
                          ),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildFavTrailing(),
        ],
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
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        final isSelect = isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space;
        if (!isSelect) return KeyEventResult.ignored;

        // Without a favorite action (or off-TV), keep press-to-play.
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
          _holdController.forward(from: 0); // fills the heart over 500ms
          return KeyEventResult.handled;
        }
        if (event is KeyUpEvent) {
          // Released before the fill completed → treat as a tap (play).
          if (!_favHoldFired) widget.onTap();
          _holdController.reset();
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
          child: row,
        ),
      ),
    );
  }

  /// Trailing favourite affordance, per input model:
  /// - TV: a non-focusable hint on the focused row ("HOLD OK" + a heart that
  ///   fills as OK is held); a small filled heart on favourited rows otherwise.
  /// - Desktop/mobile: a tappable heart, revealed on hover / when favourited /
  ///   always on touch (no hover there).
  Widget _buildFavTrailing() {
    if (widget.onFavoriteToggle == null) return const SizedBox.shrink();

    if (widget.isTelevision) {
      if (_focused) {
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: AnimatedBuilder(
            animation: _holdController,
            builder: (_, __) => _FavHint(
              favorited: widget.isFavorited,
              progress: _holdController.value,
            ),
          ),
        );
      }
      if (widget.isFavorited) {
        return const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.favorite_rounded,
              size: 18, color: Color(0xFFF43F5E)),
        );
      }
      return const SizedBox.shrink();
    }

    final show = widget.isFavorited || _active || _isTouchMobile;
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: _FavButton(
        favorited: widget.isFavorited,
        onTap: () => widget.onFavoriteToggle!(!widget.isFavorited),
      ),
    );
  }
}

/// TV favourite hint: an "HOLD OK" prompt plus a heart that fills over the hold
/// (a ring sweeps and the heart tints toward its favourited state), so the
/// hold-to-favourite gesture is visible rather than hidden.
class _FavHint extends StatelessWidget {
  final bool favorited;
  final double progress; // 0..1 hold progress
  const _FavHint({required this.favorited, required this.progress});

  @override
  Widget build(BuildContext context) {
    final holding = progress > 0.02 && progress < 1.0;
    final done = favorited || progress >= 1.0;
    final heartColor = done
        ? const Color(0xFFF43F5E)
        : Color.lerp(
            Colors.white.withValues(alpha: 0.7),
            const Color(0xFFF43F5E),
            progress,
          )!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The prompt yields to the ring once the user starts holding.
        if (!holding)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              'HOLD OK',
              style: TextStyle(
                color: HomeTheme.focusGold.withValues(alpha: 0.95),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (progress > 0.02)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    color: HomeTheme.focusGold,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              Icon(
                done
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 16,
                color: heartColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small rounded logo chip with a brand-tinted plate and a graceful fallback.
class _LogoChip extends StatelessWidget {
  final String? logoUrl;
  final String name;
  final Color brand;
  const _LogoChip({
    required this.logoUrl,
    required this.name,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(brand.withValues(alpha: 0.16),
                const Color(0xFF1E2030)),
            const Color(0xFF14141D),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: (logoUrl != null && logoUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: logoUrl!,
                fit: BoxFit.contain,
                placeholder: (_, __) => _fallback(),
                errorWidget: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 22,
        color: brand.withValues(alpha: 0.85),
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
                ? const Color(0xFFF43F5E)
                : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
