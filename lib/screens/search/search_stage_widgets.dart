part of '../search_screen.dart';

enum _CwKind { local, trakt, simkl, mdblist, iptv }

/// A leading "Continue Watching" board row (local or Trakt). Carries its own
/// header, focus nodes, per-item progress lookup, and open / quick-play
/// handlers so the local and Trakt sources render through one row builder.
class _CwRow {
  final String rowId;
  final String title; // e.g. 'Continue Watching' or 'Trakt Movies'
  final String? tag; // 'Movies' / 'Series' pill, or null
  final _CwKind kind;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final double? Function(StremioMeta) progressOf;

  /// Subtle 'S2 · E5' label for series cards (null for movies / when unknown).
  final String? Function(StremioMeta) episodeOf;

  /// Whole minutes remaining when this provider has a trustworthy duration.
  final int? Function(StremioMeta) remainingMinutesOf;

  /// Episode still for landscape series cards, resolved asynchronously and
  /// null until available. The card keeps its show-art fallback throughout.
  final String? Function(StremioMeta) episodeArtworkOf;
  final void Function(StremioMeta) onOpen;
  final void Function(StremioMeta) onQuickPlay;

  /// Takes the title off THIS row's source and reloads it. Long-press (hold-OK
  /// on TV) offers it next to Play — see [_SearchScreenState._openCwCardMenu].
  final Future<void> Function(StremioMeta) onRemove;
  final bool Function(StremioMeta)? canRemove;

  /// Opens the "See All" grid for this row's source, or null to hide the link.
  final VoidCallback? onSeeAll;

  const _CwRow({
    required this.rowId,
    required this.title,
    required this.tag,
    required this.kind,
    required this.items,
    required this.nodes,
    required this.progressOf,
    required this.episodeOf,
    required this.remainingMinutesOf,
    required this.episodeArtworkOf,
    required this.onOpen,
    required this.onQuickPlay,
    required this.onRemove,
    this.canRemove,
    this.onSeeAll,
  });
}

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

/// One Canvas rail — a Continue Watching row ([cw] non-null, with its
/// position among the CW rows in [cwIndex]), a favourites-family rail
/// ([favKind] non-null: IPTV / Debrify TV / Stremio TV / Playlist / an IPTV
/// custom-list row), or a catalog section ([sectionIndex] into
/// `_sections`/`_rowNodes`).
class _CanvasRail {
  final _CwRow? cw;
  final int cwIndex;
  final HomeFavoriteRowRef? favKind;
  final int? sectionIndex;
  final int traktSkeletonIndex;
  const _CanvasRail({
    this.cw,
    this.cwIndex = -1,
    this.favKind,
    this.sectionIndex,
    this.traktSkeletonIndex = -1,
  });
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

/// What a stage board resolved for this frame (see
/// [_SearchScreenState._resolveStageRail]) — the rail list, which one is
/// active, its identity key, its items and its focus nodes.
class _StageRailView {
  final List<_CanvasRail> rails;
  final int index;
  final _CanvasRail rail;
  final String key;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  const _StageRailView({
    required this.rails,
    required this.index,
    required this.rail,
    required this.key,
    required this.items,
    required this.nodes,
  });
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

/// One row of Tonight's Continue Watching queue: which CW rail it came from
/// and which column within it (so the cell's FocusNode, progress, episode
/// label and open/remove actions all come from the row's own contract).
class _TonightQueueEntry {
  final _CanvasRail rail;
  final int col;
  const _TonightQueueEntry({required this.rail, required this.col});
}

// The board's card focus chrome ([CardFocusRise]) moved to
// widgets/home/card_focus_rise.dart — the Discover stage's shelf wears the
// same grammar, and focus feel has to be tuned in exactly one place.

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
