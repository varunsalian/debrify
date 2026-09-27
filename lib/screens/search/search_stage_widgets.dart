part of '../search_screen.dart';

/// A reserved-but-not-yet-loaded Trakt row: a header above a strip of static
/// poster placeholders (see [_SearchScreenState._buildTraktSkeletonRow]) that
/// hold the Trakt slot open while its fetch runs. Static — nothing animates
/// while the CPU is busy loading (see [ShimmerBox]).
class _TraktSkeletonRow extends StatelessWidget {
  final Widget header;
  final double posterW;
  final double cellH;
  final double rowH;

  const _TraktSkeletonRow({
    required this.header,
    required this.posterW,
    required this.cellH,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: _SkeletonPoster(width: posterW, height: cellH),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A poster-shaped static placeholder matching the board's poster radius. Thin
/// wrapper that sizes a [ShimmerBox].
class _SkeletonPoster extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonPoster({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height, child: const ShimmerBox());
  }
}

/// What the Canvas stage should show while a FAVOURITES cell has focus —
/// favourites aren't StremioMeta, so the hero pipeline can't describe them;
/// this lightweight override carries the focused item's own art + name
/// instead (null = a catalog/CW item owns the stage as usual).
/// Paints the four corner "wedges" that make a rectangle read as a rounded
/// card — the area between the rect and its rounded inset, filled with the
/// page ink. Used instead of a ClipRRect wherever the box contains the
/// underlay trailer: a clip would introduce a saveLayer over the punch hole
/// and break its BlendMode.clear against the translucent surface, while a
/// plain fill painted ABOVE the hole is the proven pattern.
class _CornerWedges extends CustomPainter {
  final double radius;
  final Color color;
  const _CornerWedges({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerWedges old) =>
      old.radius != radius || old.color != color;
}

/// The identity block a stage shows while a FAVOURITES cell has focus.
/// Favourites aren't StremioMeta, so the logo/meta/synopsis pipeline has
/// nothing true to say about them — this is the favourite's own name and
/// source line, in the same type as the catalog identity above it.
class _StageFavIdentity extends StatelessWidget {
  final HomeFavoriteFocus fav;
  final bool centered;

  const _StageFavIdentity({required this.fav, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fav.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.core.tx,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          fav.subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.fade(app.core.tx, 0.6),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

// The board's card focus chrome ([CardFocusRise]) moved to
// widgets/home/card_focus_rise.dart — the Discover stage's shelf wears the
// same grammar, and focus feel has to be tuned in exactly one place.

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
