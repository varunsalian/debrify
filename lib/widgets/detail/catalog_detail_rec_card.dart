/// The "More Like This" recommendation card on `CatalogItemDetailScreen`.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../utils/tv_keys.dart';
import '../movie_watched_badge.dart';
import 'theme/detail_theme.dart';

// ── Recommendation ("Watch Next") card ─────────────────────────────────────

class CatalogDetailRecCard extends StatefulWidget {
  final StremioMeta item;
  final double width;
  final double posterHeight;
  final bool tv;
  final VoidCallback onTap;

  const CatalogDetailRecCard({
    super.key,
    required this.item,
    required this.width,
    required this.posterHeight,
    required this.tv,
    required this.onTap,
  });

  @override
  State<CatalogDetailRecCard> createState() => _CatalogDetailRecCardState();
}

class _CatalogDetailRecCardState extends State<CatalogDetailRecCard> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final poster = widget.item.poster;
    // Signal — this screen is never wrapped in a DetailThemeScope today, so
    // the fallback IS the shipped gold. Hoisted out of the tree below so the
    // lookup happens once per build, never inside an animated builder.
    final t = DetailThemeScope.maybeOf(context);
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (isActivateKey(event.logicalKey) ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            duration: widget.tv
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: _active ? 1.05 : 1.0,
            child: SizedBox(
              width: widget.width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: widget.width,
                      height: widget.posterHeight,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: _active
                              ? t.focus
                              : Colors.white.withValues(alpha: 0.10),
                          width: _active ? 2 : 0.5,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (poster != null && poster.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _posterFallback(),
                              errorWidget: (_, __, ___) => _posterFallback(),
                            )
                          else
                            _posterFallback(),
                          if (widget.item.type == 'movie' ||
                              widget.item.type == 'series')
                            Positioned(
                              top: 7,
                              right: 7,
                              child: MovieWatchedBadge(
                                imdbId:
                                    widget.item.effectiveImdbId ??
                                    widget.item.id,
                                contentType: widget.item.type,
                                compact: true,
                                tickPolicyScoped: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: _active ? 1.0 : 0.82,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
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

  Widget _posterFallback() => Center(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        widget.item.name,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
