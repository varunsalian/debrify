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

/// [_StremioCard] plus DPAD arrow navigation. The card owns SELECT, its
/// focus visuals and ensureVisible; this ancestor [Focus] catches the arrows
/// the card ignores (left/right within the row, up/down to adjacent rows or
/// the search field) and reports focus to drive the hero.
class _BoardCell extends StatelessWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final int column;
  final List<FocusNode> rowNodes;
  final bool hasBoundSource;
  final bool showWatchedBadge;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null (used by
  /// the Continue Watching row). Null on regular catalog rows.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut — used to
  /// mirror the catalog tiles' long-press-to-play when quick-play is available.
  final VoidCallback? onQuickPlay;

  /// Long-press (and hold-OK on TV) opens a menu instead of playing. Set on
  /// Continue Watching cards, where the press has to offer removal too; takes
  /// precedence over [onQuickPlay] when both are given.
  final VoidCallback? onLongPress;
  final VoidCallback onFocused;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onOpen;

  /// Called when DPAD-right focus nears this row's last card, so the next page
  /// can be prefetched before the user runs out of cards. Null on rows that
  /// don't paginate (e.g. Continue Watching).
  final VoidCallback? onNearEnd;

  /// Shared-element tag forwarded to the card (see [_StremioCard.heroTag]).
  final String? heroTag;

  /// Forwarded to [_StremioCard.ringColor] (Canvas cells use white).
  final Color? ringColor;

  /// Cell shape + the art that fills it. Defaults are the 2:3 poster every
  /// row uses; Promenade's strip passes 16/9 with a derived wide still.
  final double aspectRatio;
  final String? artUrl;
  final String? focusArtUrl;
  final bool showTitleOverlay;

  /// Dim applied to this cell while it is NOT focused (Promenade's strip).
  final Color? restVeil;

  /// HELD up/down — fired on the first key REPEAT instead of [onUp]/[onDown].
  /// Tonight uses it to escape a long Continue queue in one gesture rather
  /// than one row at a time. Null keeps a held key doing what a tapped one
  /// does (the fast-scroll every rail relies on).
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;

  /// Horizontal overrides. Null keeps the row grammar (LEFT walks back along
  /// [rowNodes] and hands off to the sidebar at column 0; RIGHT walks forward
  /// and prefetches). Mosaic's GRID must override both — its leftmost cell is
  /// not column 0, so without this the sidebar would be unreachable from
  /// every row but the first — and Tonight's queue overrides them too.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _BoardCell({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.column,
    required this.rowNodes,
    required this.hasBoundSource,
    this.showWatchedBadge = true,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    this.onLongPress,
    required this.onFocused,
    required this.onUp,
    required this.onDown,
    required this.onOpen,
    this.onNearEnd,
    this.heroTag,
    this.ringColor,
    this.onLeft,
    this.onRight,
    this.aspectRatio = 2 / 3,
    this.artUrl,
    this.focusArtUrl,
    this.showTitleOverlay = true,
    this.restVeil,
    this.onUpHold,
    this.onDownHold,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    // Act on key-down AND key-repeat (held DPAD). If we let a repeat fall
    // through as `ignored`, Flutter's default geometric traversal fires and
    // jumps focus into an adjacent row — so only key-ups are passed on.
    if (!isTelevision || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (onLeft != null) {
        onLeft!();
      } else if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        // First card in the row — leave to the sidebar (no leading tile now).
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Prefetch the next page a few cards before the end so DPAD users never
      // hit a wall on a catalog that still has more.
      if (column >= rowNodes.length - 6) onNearEnd?.call();
      if (onRight != null) {
        onRight!();
      } else if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyRepeatEvent && onUpHold != null) {
        onUpHold!();
      } else {
        onUp();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && onDownHold != null) {
        onDownHold!();
      } else {
        onDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has) onFocused();
      },
      onKeyEvent: _handleArrows,
      child: _StremioCard(
        item: item,
        isTelevision: isTelevision,
        focusNode: focusNode,
        hasBoundSource: hasBoundSource,
        showWatchedBadge: showWatchedBadge,
        ringColor: ringColor,
        progress: progress,
        episodeLabel: episodeLabel,
        onQuickPlay: onQuickPlay,
        onLongPress: onLongPress,
        onOpen: onOpen,
        heroTag: heroTag,
        aspectRatio: aspectRatio,
        artUrl: artUrl,
        focusArtUrl: focusArtUrl,
        showTitleOverlay: showTitleOverlay,
        restVeil: restVeil,
      ),
    );
  }
}

/// Hero flight for poster→detail-backdrop: always show the POSTER side of the
/// pair (the `from` hero on push, the `to` hero on pop), so the artwork the
/// user tapped is what grows into / shrinks out of the detail page — never a
/// half-loaded backdrop.
Widget _posterFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final Hero posterHero =
      (direction == HeroFlightDirection.push
              ? fromHeroContext.widget
              : toHeroContext.widget)
          as Hero;
  // The shuttle renders in the root overlay, outside any Material — wrap so a
  // text placeholder (missing poster art) can't render unstyled mid-flight.
  return Material(type: MaterialType.transparency, child: posterHero.child);
}

/// Metahub title-logo URL derived synchronously from an IMDb id (same trick
/// the hero uses) — lets the Canvas identity show studio title art without
/// waiting for /meta enrichment. Null when the item has no IMDb-shaped id.
String? _metahubLogoUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null ? null : 'https://images.metahub.space/logo/medium/$tt/img';
}

/// Metahub 16:9 still, derived the same synchronous way — catalog items carry
/// a poster but rarely a backdrop, and the wide-cell layouts (Promenade's
/// strip, Tonight's queue) need landscape art the moment a rail paints, not
/// after /meta enrichment. Null when the item has no IMDb-shaped id.
String? _metahubBackgroundUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null
      ? null
      : 'https://images.metahub.space/background/medium/$tt/img';
}

/// Best available wide art for a 16:9 cell: whatever the item already carries,
/// then the derived metahub still, then the poster (cover-cropped) so a cell
/// is never empty.
String? _wideArtUrl(StremioMeta item) =>
    _firstNonEmpty(item.background, _metahubBackgroundUrl(item)) ??
    _firstNonEmpty(item.poster, null);

/// Whether [enriched] describes the same title as [item]. Raw id equality is
/// not enough: an addon can list a title as `tmdb:603` while the /meta
/// record — fetched via the IMDb id the addon supplied — comes back as
/// `tt0133093`. Compare canonical IMDb identity too, or valid enrichment
/// gets rejected and Canvas loses its backdrop/description/rating.
bool _sameCanvasTitle(StremioMeta item, StremioMeta enriched) {
  if (enriched.id == item.id) return true;
  final itTt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  final enTt =
      enriched.imdbId ?? (enriched.id.startsWith('tt') ? enriched.id : null);
  return itTt != null && itTt == enTt;
}

/// First non-empty of two optional strings (merge helper: enriched field
/// wins only when it actually carries a value).
String? _firstNonEmpty(String? a, String? b) =>
    (a != null && a.isNotEmpty) ? a : ((b != null && b.isNotEmpty) ? b : null);

/// One Canvas rail — a Continue Watching row ([cw] non-null, with its
/// position among the CW rows in [cwIndex]), a favourites-family rail
/// ([favKind] non-null: IPTV / Debrify TV / Stremio TV / Playlist / an IPTV
/// custom-list row), or a catalog section ([sectionIndex] into
/// `_sections`/`_rowNodes`).
class _CanvasRail {
  final _CwRow? cw;
  final int cwIndex;
  final _FavRowRef? favKind;
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
  final _CanvasFavFocus fav;
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

/// What Tonight's big card says about the focused entry. Derived per focus —
/// the OK hint has to tell the truth: a part-watched title resumes, a catalog
/// title opens, a favourite is watched.
class _TonightCardInfo {
  /// What OK actually does — never what the layout wishes it did. Continue
  /// Watching cards open their detail page on OK across the whole app, and
  /// Tonight keeps that grammar rather than diverging.
  final String action;

  /// What a HELD OK does, when that differs (resume, or the card menu).
  final String? holdAction;
  final String? episode;
  final double? progress;
  const _TonightCardInfo({
    required this.action,
    this.holdAction,
    this.episode,
    this.progress,
  });
}

/// The caption block on Tonight's card: title art, what you are about to do,
/// the episode, how much is left and the progress bar. Everything is driven
/// by listenables so a DPAD move repaints this block alone.
class _TonightCardCaption extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final ValueListenable<_CanvasFavFocus?> fav;
  final ValueListenable<_TonightCardInfo?> info;

  const _TonightCardCaption({
    required this.item,
    required this.enriched,
    required this.fav,
    required this.info,
  });

  /// Minutes left from a '60 min'-shaped runtime and a 0..1 progress.
  static String? _timeLeft(String? runtime, double? progress) {
    if (runtime == null || progress == null || progress <= 0) return null;
    final m = RegExp(r'(\d+)').firstMatch(runtime);
    if (m == null) return null;
    final total = int.tryParse(m.group(1)!);
    if (total == null || total <= 0) return null;
    final left = ((1 - progress.clamp(0.0, 1.0)) * total).round();
    return left <= 0 ? null : '$left min left';
  }

  @override
  Widget build(BuildContext context) {
    // Hoisted: `fav` fires on every focus move across the Tonight rail.
    final tx = AppThemeScope.of(context).core.tx;
    return ValueListenableBuilder<_CanvasFavFocus?>(
      valueListenable: fav,
      builder: (context, favFocus, _) {
        if (favFocus != null) {
          return _block(
            context,
            hold: null,
            titleWidget: Text(
              favFocus.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tx,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
              ),
            ),
            line: favFocus.subtitle,
            action: 'Watch',
            progress: null,
          );
        }
        return ValueListenableBuilder<StremioMeta?>(
          valueListenable: item,
          builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
            valueListenable: enriched,
            builder: (context, en, _) =>
                ValueListenableBuilder<_TonightCardInfo?>(
                  valueListenable: info,
                  builder: (context, nfo, _) {
                    final it0 = it;
                    if (it0 == null) return const SizedBox.shrink();
                    final enr = (en != null && _sameCanvasTitle(it0, en))
                        ? en
                        : null;
                    final logo =
                        _firstNonEmpty(enr?.logo, it0.logo) ??
                        _metahubLogoUrl(it0);
                    final runtime = _firstNonEmpty(enr?.runtime, it0.runtime);
                    final left = _timeLeft(runtime, nfo?.progress);
                    final parts = <String>[
                      if (nfo?.episode != null) nfo!.episode!,
                      if (left != null) left else if (runtime != null) runtime,
                      if (nfo?.episode == null && left == null)
                        (it0.type == 'series' ? 'SERIES' : 'MOVIE'),
                    ];
                    return _block(
                      context,
                      hold: nfo?.holdAction,
                      titleWidget: logo != null
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 46,
                                maxWidth: 300,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: logo,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                memCacheWidth: 400,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) =>
                                    const SizedBox(height: 46),
                                errorWidget: (_, __, ___) =>
                                    _fallbackTitle(it0.name),
                              ),
                            )
                          : _fallbackTitle(it0.name),
                      line: parts.join('  ·  '),
                      action: nfo?.action ?? 'Open',
                      progress: nfo?.progress,
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  static Widget _fallbackTitle(String name) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
    ),
  );

  Widget _block(
    BuildContext context, {
    required Widget titleWidget,
    required String line,
    required String action,
    required String? hold,
    required double? progress,
  }) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.74),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (hold != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: app.fade(app.core.tx, 0.30)),
                  borderRadius: app.shape.br(20),
                ),
                child: Text(
                  'HOLD  $hold',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: app.core.tx.withValues(alpha: 0.92),
                borderRadius: app.shape.br(20),
              ),
              child: Text(
                'OK  $action',
                style: const TextStyle(
                  color: Color(0xFF12101F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        if (progress != null && progress > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: app.shape.br(3),
            child: SizedBox(
              height: 5,
              child: ColoredBox(
                color: app.core.tx.withValues(alpha: 0.22),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of Tonight's Continue queue: a 16:9 still, the title, the episode
/// and a progress bar. Carries the same focus grammar and the same hold-OK
/// menu as a Continue Watching card, so nothing is lost by laying the row out
/// horizontally instead of as a poster.
class _TonightQueueRow extends StatefulWidget {
  final StremioMeta item;
  final double height;

  /// Width of the still. Capped by the row's width upstream — see
  /// [_SearchScreenState._tonightQueueList].
  final double thumbWidth;
  final FocusNode focusNode;
  final String? episode;
  final double? progress;

  /// Mirrors the board cards' bookmark mark — a title with a source already
  /// bound plays without picking one, and that is worth seeing here too.
  final bool hasBoundSource;
  final VoidCallback onFocused;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Held DOWN — see [_BoardCell.onDownHold]. Null keeps a held key stepping
  /// one row at a time.
  final VoidCallback? onDownHold;
  final VoidCallback onLeft;

  const _TonightQueueRow({
    required this.item,
    required this.height,
    required this.thumbWidth,
    required this.focusNode,
    required this.episode,
    required this.progress,
    required this.hasBoundSource,
    required this.onFocused,
    required this.onOpen,
    required this.onLongPress,
    required this.onUp,
    required this.onDown,
    this.onDownHold,
    required this.onLeft,
  });

  @override
  State<_TonightQueueRow> createState() => _TonightQueueRowState();
}

class _TonightQueueRowState extends State<_TonightQueueRow>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _keyDown = false;
  bool _holdFired = false;
  bool _holding = false;

  /// Same 500ms hold-OK the Continue Watching cards use.
  static const _holdDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _holdFired = true;
        setState(() => _holding = false);
        _holdController.reset();
        widget.onLongPress();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _cancelHold() {
    _holdController.reset();
    if (_holding && mounted) setState(() => _holding = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (isActivateKey(event.logicalKey) ||
          event.logicalKey == LogicalKeyboardKey.space) {
        final wasPress = _keyDown && !_holdFired;
        _keyDown = false;
        _holdFired = false;
        _cancelHold();
        if (wasPress) widget.onOpen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _keyDown = true;
        _holdFired = false;
        setState(() => _holding = true);
        _holdController.forward(from: 0);
      }
      // Swallow auto-repeat while held.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && widget.onDownHold != null) {
        widget.onDownHold!();
      } else {
        widget.onDown();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Nothing to the right of the queue — swallow it so Flutter's geometric
      // traversal can't wander into the rail below.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final h = widget.height;
    final thumbW = widget.thumbWidth;
    final art = _wideArtUrl(widget.item);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) {
          _keyDown = false;
          _holdFired = false;
          _cancelHold();
        } else {
          widget.onFocused();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onOpen,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: h,
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, _focused ? 0.10 : 0.045),
            borderRadius: app.shape.br(10),
            border: Border.all(
              color: _focused ? app.core.tx : app.fade(app.core.tx, 0.06),
              width: _focused ? 2.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: app.shape.br(9),
            child: Row(
              children: [
                SizedBox(
                  width: thumbW,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xFF171426)),
                      if (art != null && art.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: art,
                          fit: BoxFit.cover,
                          memCacheWidth: 420,
                          fadeInDuration: HomeTheme.imageFadeIn(true),
                          fadeOutDuration: HomeTheme.imageFadeOut(true),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      if (widget.hasBoundSource)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            Icons.bookmark_rounded,
                            size: 15,
                            color: app.core.tx,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 6),
                            ],
                          ),
                        ),
                      if (_holding) const ColoredBox(color: Color(0x730A0810)),
                      if (_holding)
                        Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: AnimatedBuilder(
                              animation: _holdController,
                              builder: (context, _) =>
                                  CircularProgressIndicator(
                                    value: _holdController.value,
                                    strokeWidth: 2.5,
                                    color: app.core.tx,
                                    backgroundColor: Colors.white24,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: app.core.tx,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (widget.episode != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            widget.episode!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: app.fade(app.core.tx, 0.56),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (widget.progress != null) ...[
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: app.shape.br(2),
                            child: SizedBox(
                              height: 4,
                              child: ColoredBox(
                                // 0.18 vanished against the row's own panel,
                                // so the fill read as a dash floating in
                                // space rather than a bar with a track.
                                color: app.core.tx.withValues(alpha: 0.28),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: widget.progress!.clamp(0.0, 1.0),
                                  heightFactor: 1,
                                  child: const ColoredBox(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

class _CanvasFavFocus {
  final String? art;
  final BoxFit fit;
  final String title;
  final String subtitle;
  const _CanvasFavFocus({
    required this.art,
    this.fit = BoxFit.cover,
    required this.title,
    required this.subtitle,
  });
}

/// Canvas stage floor + full-bleed key art for the settled hero item. Sits
/// BELOW the underlay punch hole; the AnimatedSwitcher fade wraps only this
/// sibling, never the engine, so the hole's BlendMode.clear is untouched.
/// Metahub backdrop URLs that came back 404 this session — the same
/// memo the title-logo art keeps, for the same reason: without it every
/// focus on a title with no derived still re-requests a known-dead URL.
///
/// Bounded: a long session browsing paginated catalogs would otherwise keep
/// every miss for the life of the process. A full clear is fine — the cost of
/// forgetting is one re-request per title, exactly what the memo saves.
final Set<String> _deadBackdropUrls = <String>{};
const int _kDeadBackdropMemoMax = 512;

void _rememberDeadBackdrop(String url) {
  if (_deadBackdropUrls.length >= _kDeadBackdropMemoMax) {
    _deadBackdropUrls.clear();
  }
  _deadBackdropUrls.add(url);
}

class _CanvasArtLayer extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final int cacheWidth;
  final int cacheHeight;

  /// Non-null while a favourites cell has focus: its art overrides the hero
  /// pipeline's (contain-fit logos render centred over the floor instead of
  /// being cover-stretched across the canvas).
  final ValueListenable<_CanvasFavFocus?> fav;

  const _CanvasArtLayer({
    required this.item,
    required this.enriched,
    required this.fav,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) => ValueListenableBuilder<_CanvasFavFocus?>(
          valueListenable: fav,
          builder: (context, fav, _) {
            // Enrichment merged over the catalog item: matched by canonical
            // IMDb identity (ids can differ in form), and a sparse /meta
            // record can't erase a backdrop the catalog already carried.
            final enr = (it != null && en != null && _sameCanvasTitle(it, en))
                ? en
                : null;
            // WIDE art first. The old chain fell straight from "no backdrop"
            // to the POSTER, which a 16:9 box has to crop to a horizontal
            // slice — on a title whose poster is a row of character portraits
            // that reads as several unrelated images stacked in one card. The
            // metahub still (derived synchronously from the IMDb id, exactly
            // like the title logo) is a real landscape frame and exists for
            // most titles; the poster stays as the last resort, applied by the
            // error branch below so a 404 still lands on something.
            final wide = it == null
                ? null
                : _firstNonEmpty(enr?.background, it.background) ??
                      (_deadBackdropUrls.contains(
                            _metahubBackgroundUrl(it) ?? '',
                          )
                          ? null
                          : _metahubBackgroundUrl(it));
            final posterUrl = (it?.poster?.isNotEmpty ?? false)
                ? it!.poster
                : null;
            final bg = wide ?? posterUrl ?? '';
            final Widget art;
            final favArt = fav?.art;
            if (fav != null) {
              if (favArt == null || favArt.isEmpty) {
                art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
              } else if (fav.fit == BoxFit.contain) {
                art = Center(
                  key: ValueKey('canvas-fav-logo-$favArt'),
                  child: FractionallySizedBox(
                    widthFactor: 0.38,
                    heightFactor: 0.38,
                    child: CachedNetworkImage(
                      imageUrl: favArt,
                      fit: BoxFit.contain,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                );
              } else {
                art = CachedNetworkImage(
                  key: ValueKey(
                    'canvas-fav-art-$favArt-${cacheWidth}x$cacheHeight',
                  ),
                  imageUrl: favArt,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: cacheWidth,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
              }
            } else if (bg.isEmpty) {
              art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
            } else {
              // A derived metahub still can 404 (not every title has one).
              // Remember that so the next focus doesn't ask again, and fall
              // back to the poster in place rather than to an empty stage.
              final derived =
                  wide != null &&
                  wide != enr?.background &&
                  wide != it?.background;
              art = CachedNetworkImage(
                key: ValueKey('$bg-${cacheWidth}x$cacheHeight'),
                imageUrl: bg,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: wide != null ? cacheWidth : null,
                memCacheHeight: wide == null ? cacheHeight : null,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) {
                  if (derived) _rememberDeadBackdrop(bg);
                  if (posterUrl == null || bg == posterUrl) {
                    return const SizedBox.shrink();
                  }
                  return CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    memCacheHeight: cacheHeight,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  );
                },
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                // Opaque floor: the app shell can never show through a missing
                // or still-decoding backdrop.
                ColoredBox(color: app.home.bg),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  // AnimatedSwitcher's DEFAULT layout centres its children under
                  // LOOSE constraints, so a BoxFit.cover image sizes to its own
                  // aspect instead of the box. On Canvas the box is the whole
                  // 16:9 screen and it looked identical either way — but Atrium's
                  // art column is nearly square, and there the backdrop
                  // letterboxed with ink bands above and below it. Expand both
                  // the incoming and outgoing child so "cover" means the box.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: art,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The Canvas stage's constant lighting: a left column scrim (identity
/// legibility), a bottom ramp (tabs/shelf legibility) and a bottom-left
/// "text pocket" — a soft radial wash under the identity block. Premium OTT
/// scrims are far heavier than they look (85-95% ink at the text baseline);
/// because the falloff is gradual and in the page's own ink colour it reads
/// as LIGHTING, never as a plate behind the text — bright art (snow, skies,
/// white key art) stays legible without the stage going flat. Painted ABOVE
/// both the idle art and the live video — plain gradient draws over the
/// punch hole, the same on-device-proven pattern as the region feathers.
/// How a stage lights its art. Every variant is a set of CONSTANT gradients
/// painted above the art AND the video — plain draws over the punch hole, the
/// on-device-proven pattern (never an Opacity wrapper, never a tween).
enum _StageScrimVariant {
  /// Canvas / Deck / Tonight: left column + bottom ramp + a bottom-left text
  /// pocket, seating an edge-anchored identity block.
  canvas,

  /// Promenade: symmetric — a bottom ramp for the strip, a centred pocket
  /// under the identity, and a light top wash so the trailer pill reads.
  centered,

  /// Atrium: the art is a COLUMN, so the only left lighting it needs is a
  /// narrow feather melting into the ink panel at the seam, plus a bottom
  /// ramp under the poster wall.
  seam,
}

class _CanvasScrims extends StatelessWidget {
  /// Theater mode: ALL the stage lighting fades — the left column scrim, the
  /// bottom ramp and the text pocket exist to seat text and shelf that have
  /// receded, so the video gets the truly clean frame (the logo, gliding to
  /// the top-left corner, carries its own art shadows).
  final bool theater;

  final _StageScrimVariant variant;

  const _CanvasScrims({
    this.theater = false,
    this.variant = _StageScrimVariant.canvas,
  });

  static const _canvasLayers = <Widget>[
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF00D0B1A), Color(0xA80D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.32, 0.66],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xC20D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.20, 0.50],
        ),
      ),
    ),
    // The text pocket: centred under the identity block (lower-left
    // quadrant), dissolving well before mid-screen so the art/video
    // keeps its glow everywhere else.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.72, 0.55),
          radius: 0.95,
          colors: [Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.12, 1.0],
        ),
      ),
    ),
  ];

  static const _centeredLayers = <Widget>[
    // Bottom ramp — deeper than Canvas's: the strip sits lower and the
    // identity stands directly on it.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF70D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.24, 0.56],
        ),
      ),
    ),
    // Centre pocket: the symmetric twin of Canvas's corner pocket, seating
    // the centred logo + meta without flattening the frame's edges.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.30),
          radius: 0.78,
          colors: [Color(0xB80D0B1A), Color(0x000D0B1A)],
          stops: [0.10, 1.0],
        ),
      ),
    ),
    // A whisper at the top so the TRAILER pill never sits on bright sky.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x730D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.22],
        ),
      ),
    ),
  ];

  static const _seamLayers = <Widget>[
    // The seam: a narrow melt into the ink panel on the left. Short, so the
    // art keeps its width — the panel beside it already carries the text.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF20D0B1A), Color(0x8C0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.07, 0.22],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.36, 0.76],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final layers = switch (variant) {
      _StageScrimVariant.canvas => _canvasLayers,
      _StageScrimVariant.centered => _centeredLayers,
      _StageScrimVariant.seam => _seamLayers,
    };
    return AnimatedOpacity(
      opacity: theater ? 0.0 : 1.0,
      duration: theater
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }
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
          final enr = (en != null && _sameCanvasTitle(it0, en)) ? en : null;
          final logo =
              _firstNonEmpty(enr?.logo, it0.logo) ?? _metahubLogoUrl(it0);
          final rating = enr?.imdbRating ?? it0.imdbRating;
          final year = _firstNonEmpty(enr?.year, it0.year);
          final runtime = _firstNonEmpty(enr?.runtime, it0.runtime);
          final genres = (enr?.genres != null && enr!.genres!.isNotEmpty)
              ? enr.genres
              : it0.genres;
          final description = _firstNonEmpty(enr?.description, it0.description);
          final titleText = Text(
            it0.name,
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
