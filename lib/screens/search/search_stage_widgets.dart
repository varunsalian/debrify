part of '../search_screen.dart';

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

// The board's card focus chrome ([CardFocusRise]) moved to
// widgets/home/card_focus_rise.dart — the Discover stage's shelf wears the
// same grammar, and focus feel has to be tuned in exactly one place.

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
