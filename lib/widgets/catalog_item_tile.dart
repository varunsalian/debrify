import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import 'home/home_theme.dart';

/// Poster-first grid tile for catalog and search results.
///
/// Tap (or D-pad SELECT) calls [onOpen]. Description, year, genres and
/// per-item actions live on the detail screen — the grid stays clean.
class CatalogItemTile extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode? focusNode;
  final bool hasBoundSource;
  final VoidCallback onOpen;

  const CatalogItemTile({
    super.key,
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.hasBoundSource,
    required this.onOpen,
  });

  @override
  State<CatalogItemTile> createState() => _CatalogItemTileState();
}

class _CatalogItemTileState extends State<CatalogItemTile> {
  bool _focused = false;
  bool _hovered = false;

  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final poster = item.poster;
    final rating = item.imdbRating;
    final typeLabel = item.type == 'series' ? 'SERIES' : 'MOVIE';

    final card = AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      scale: _active ? 1.08 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _active ? 0.7 : 0.35),
              blurRadius: _active ? 38 : 14,
              offset: const Offset(0, 14),
            ),
            if (_active) ...[
              // Tight bright gold rim.
              BoxShadow(
                color: HomeTheme.focusGold.withValues(alpha: 0.6),
                blurRadius: 30,
                spreadRadius: 1,
              ),
              // Wide warm amber bloom for the cinematic falloff.
              BoxShadow(
                color: HomeTheme.focusGoldDeep.withValues(alpha: 0.32),
                blurRadius: 90,
                spreadRadius: 10,
              ),
            ],
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster != null && poster.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: poster,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _placeholder(item.name),
                  errorWidget: (_, __, ___) => _placeholder(item.name),
                )
              else
                _placeholder(item.name),

              // Bottom gradient — only when focused — for the inline title.
              if (_active)
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

              Positioned(
                top: 10,
                left: 10,
                child: _GlassChip(label: typeLabel),
              ),

              if (rating != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _RatingChip(value: rating),
                ),

              if (widget.hasBoundSource)
                const Positioned(
                  bottom: 10,
                  right: 10,
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 18,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                  ),
                ),

              // Focused title overlay — appears inside the poster on focus
              // so the chrome below the tile stays calm.
              if (_active)
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
                            color: Colors.white,
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
                                color: Colors.white.withValues(alpha: 0.7),
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

              if (_active)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
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
          // Scroll the focused tile to the middle of the grid so the whole
          // (scaled-up) card is visible instead of being clipped at an edge.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      ),
    );
  }

  Widget _placeholder(String title) {
    return Container(
      color: const Color(0xFF111118),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  final double value;
  const _RatingChip({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
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
            style: const TextStyle(
              color: Colors.white,
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
