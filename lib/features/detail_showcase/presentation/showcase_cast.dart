import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/services/imdb_enrichment_service.dart' show CastMember;
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';

// ── cast ───────────────────────────────────────────────────────────────────

class ShowcaseCast extends StatelessWidget {
  final List<CastMember> cast;
  final List<FocusNode> nodes;
  final ValueChanged<CastMember>? onPersonOpen;

  const ShowcaseCast({
    super.key,
    required this.cast,
    required this.nodes,
    this.onPersonOpen,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return SBand(
      title: 'Cast & Crew',
      height: m.circle * 1.08 + 46 * m.k,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: cast.length,
        separatorBuilder: (_, __) => SizedBox(width: m.castGap),
        itemBuilder: (context, i) => _CastTile(
          member: cast[i],
          node: nodes[i],
          size: m.circle,
          onTap: onPersonOpen != null && (cast[i].tmdbPersonId ?? 0) > 0
              ? () => onPersonOpen!(cast[i])
              : null,
        ),
      ),
    );
  }
}

class _CastTile extends StatefulWidget {
  final CastMember member;
  final FocusNode node;
  final double size;
  final VoidCallback? onTap;

  const _CastTile({
    required this.member,
    required this.node,
    required this.size,
    this.onTap,
  });

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final url = ViewportArtworkScope.enabledOf(context)
        ? widget.member.imageUrl
        : null;
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) sKeepVisible(context);
      },
      onKeyEvent: (_, event) => sActivate(event, widget.onTap),
      child: Semantics(
        button: widget.onTap != null,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: SHover(
            cursor: widget.onTap != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            builder: (context, hovered) => SizedBox(
              width: widget.size,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParallaxFocus(
                    focused: _f || hovered,
                    shape: ParallaxShape.castCircle,
                    radius: BorderRadius.circular(widget.size / 2),
                    child: ClipOval(
                      child: SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: (url != null && url.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                cacheManager: DebrifyImageCache.manager,
                                memCacheWidth: 260,
                                placeholder: (_, __) =>
                                    const ColoredBox(color: Color(0xFF4A4A55)),
                                errorWidget: (_, __, ___) =>
                                    const ColoredBox(color: Color(0xFF4A4A55)),
                              )
                            : const ColoredBox(color: Color(0xFF4A4A55)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    widget.member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: st(12.5 * k),
                  ),
                  if ((widget.member.character ?? '').isNotEmpty)
                    Text(
                      widget.member.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: st(11.5 * k, a: 0.55),
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
