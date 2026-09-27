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

/// How a stage sets its identity block.
enum _StageIdentityVariant {
  /// Canvas / Deck / Tonight: bottom-left, one meta line, three-line synopsis.
  stage,

  /// Atrium: a narrow ink column — the meta breaks onto two lines (facts, then
  /// genres) so it can never overrun the column, and the synopsis gets a
  /// fourth line because there is room for it.
  narrow,

  /// Promenade: centred, no synopsis — the composition is the point.
  centered,

  /// Mosaic: a fixed-height band above the wall — logo and one meta line,
  /// left-aligned, no synopsis (the grid is the content; this is a caption).
  headline,
}

/// The height a [_StageIdentityVariant.narrow] block needs before its synopsis
/// is worth reserving: logo, two meta lines, the slot itself and the air
/// between them, at the current text scale. Below this the caller asks for
/// [_StageIdentityVariant.headline] instead of clipping.
double _stageNarrowIdentityH(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  return 56 + 10 + t.scale(23) * 1.3 * 2 + 6 + 10 + 78;
}

/// Canvas identity block: logo title-art (held EMPTY while loading, text only
/// when there's no URL or it 404s — the C5 "no text→logo flash" rule) over a
/// quiet meta line with the gold IMDb mark and a three-line synopsis. While
/// the ambient trailer plays, meta + synopsis fade away and the LOGO HOLDS
/// THE STAGE (the classic hero's premium move); any DPAD move brings them
/// back with the lights.
class _CanvasIdentity extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;

  /// True while ambient video owns the stage — drives the meta/synopsis fade.
  final ValueListenable<bool> trailerShowing;

  final _StageIdentityVariant variant;

  /// Width the block may occupy — the text column's real width, so the logo
  /// and synopsis are capped by geometry rather than by a guess.
  final double maxWidth;

  const _CanvasIdentity({
    required this.item,
    required this.enriched,
    required this.trailerShowing,
    this.variant = _StageIdentityVariant.stage,
    this.maxWidth = 430,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final centered = variant == _StageIdentityVariant.centered;
    final narrow = variant == _StageIdentityVariant.narrow;
    final headline = variant == _StageIdentityVariant.headline;
    final noSynopsis = centered || headline;
    // The stage variant is Canvas's, and Canvas never capped its title or
    // meta line — only the synopsis. Keep that exactly, or long logo-less
    // titles start ellipsising where they never used to.
    final capWidth = variant != _StageIdentityVariant.stage;
    Widget capped(Widget child) => capWidth
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          )
        : child;
    final cross = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final align = centered ? TextAlign.center : TextAlign.start;
    final double logoMaxW = centered
        ? 380
        : min(maxWidth, narrow ? 340 : (headline ? 360 : 300));
    final double logoMaxH = centered ? 66 : (headline ? _kMosaicLogoH : 56);
    // Fixed synopsis slot (see below) — 3 lines on a stage, 4 in a column.
    final int synLines = narrow ? 4 : 3;
    final double synSlot = narrow ? 78 : 58;

    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) {
          final it0 = it;
          if (it0 == null) return const SizedBox.shrink();
          // Enrichment merged over the catalog item FIELD BY FIELD: matched
          // by canonical IMDb identity (catalog ids can be tmdb:… while the
          // /meta record is tt…), and a sparse /meta response — it may carry
          // only a rating — can never erase what the catalog already knew.
          final enr = (en != null && sameHomeStageTitle(it0, en)) ? en : null;
          final fields = HeroMetadataFields(it0, enr);
          final logo =
              fields.logo ??
              (fields.allowArtworkFallback ? homeStageLogoUrl(it0) : null);
          final rating = enr?.imdbRating ?? it0.imdbRating;
          final year = homeStageFirstNonEmpty(enr?.year, it0.year);
          final runtime = fields.runtime;
          final genres = fields.genres;
          final description = fields.description;
          final titleText = Text(
            fields.name,
            maxLines: narrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: app.core.tx,
              fontSize: headline ? _kStageHeadlineTitleSize : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.05,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
            ),
          );
          final genreText = (genres != null && genres.isNotEmpty)
              ? genres.take(2).join(' · ')
              : null;
          // The narrow column splits the line rather than ellipsising it.
          final metaParts = <String>[
            it0.type == 'series' ? 'SERIES' : 'MOVIE',
            if (year != null) year,
            if (runtime != null) runtime,
            if (!narrow && !headline && genreText != null) genreText,
          ];
          // Headline stands in for narrow on short columns, so it wraps the
          // genres the same way — in the facts row they would just be the
          // first thing ellipsised away.
          final wrapGenres = narrow || headline;
          final metaStyle = TextStyle(
            color: app.fade(app.core.tx, 0.7),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          );
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            // AnimatedSwitcher's DEFAULT layout centers its child — which
            // floated the whole identity block to mid-screen, off the left
            // scrim column it was designed to stand on. Pin it to the edge
            // the variant is anchored to.
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: centered
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: Column(
              key: ValueKey('canvas-id-${it0.id}'),
              crossAxisAlignment: cross,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: logoMaxW,
                      maxHeight: logoMaxH,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      alignment: centered
                          ? Alignment.bottomCenter
                          : Alignment.bottomLeft,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => SizedBox(height: logoMaxH),
                      errorWidget: (_, __, ___) => capped(titleText),
                    ),
                  )
                else
                  capped(titleText),
                const SizedBox(height: 10),
                // Meta + synopsis fade while the ambient trailer plays; the
                // logo above stays. Sibling-above-the-hole opacity — the
                // on-device-proven overlay pattern (region feathers/chip).
                ValueListenableBuilder<bool>(
                  valueListenable: trailerShowing,
                  builder: (context, showing, kid) => AnimatedOpacity(
                    opacity: showing ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOut,
                    child: kid,
                  ),
                  child: Column(
                    crossAxisAlignment: cross,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      capped(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: centered
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            if (rating != null) ...[
                              const Text(
                                'IMDb',
                                style: TextStyle(
                                  color: Color(0xFFF5C518),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: app.fade(app.core.tx, 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: app.fade(app.core.tx, 0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            Flexible(
                              child: Text(
                                metaParts.join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Narrow columns carry genres on their own line rather
                      // than ellipsising the facts away.
                      if (wrapGenres && genreText != null) ...[
                        const SizedBox(height: 6),
                        capped(
                          Text(
                            genreText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle.copyWith(
                              color: app.fade(app.core.tx, 0.46),
                            ),
                          ),
                        ),
                      ],
                      // Fixed-height synopsis slot: the description usually
                      // lands ~300ms after the settle (/meta enrichment), and
                      // this block is BOTTOM-anchored — reserving the lines
                      // keeps the logo from jumping when the text arrives.
                      // Promenade has no synopsis at all, so it reserves
                      // nothing.
                      if (!noSynopsis) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: synSlot,
                          child: description != null
                              ? ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxWidth,
                                  ),
                                  child: Text(
                                    description,
                                    maxLines: synLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: app.fade(app.core.tx, 0.78),
                                      fontSize: 12.5,
                                      height: 1.5,
                                      fontWeight: FontWeight.w500,
                                      // Crisp, tight shadow — a seasoning under
                                      // the scrim, never a smear (big radii
                                      // read as muddy text on TV panels).
                                      shadows: const [
                                        Shadow(
                                          color: Color(0xBF000000),
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// The board's card focus chrome ([CardFocusRise]) moved to
// widgets/home/card_focus_rise.dart — the Discover stage's shelf wears the
// same grammar, and focus feel has to be tuned in exactly one place.

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
