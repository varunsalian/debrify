import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';

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
