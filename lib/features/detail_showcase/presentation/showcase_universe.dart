import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/services/imdb_enrichment_service.dart'
    show UniverseTitle;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';

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
