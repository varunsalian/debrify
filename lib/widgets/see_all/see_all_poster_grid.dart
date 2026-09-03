import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../theme/app_theme_scope.dart';
import '../catalog_item_tile.dart';
import 'discover_card_settings_scope.dart';
import 'discover_shelf_scope.dart';

/// The single source of truth for a See-All poster grid's layout maths: column
/// count, cell size and the spacing/padding constants. Both the real grid
/// ([SeeAllPosterGrid]) and its loading placeholder (SkeletonPosterGrid) resolve
/// geometry through here, so the placeholder hands off to the real posters with
/// zero layout shift — the two can't drift because there's only one formula.
class SeeAllGridMetrics {
  final int columns;
  final double childWidth;

  /// Full cell height: a 2:3 poster + [titleGap] + a 2-line [titleHeight] band.
  final double cellHeight;

  /// Height of the 2-line title band below each poster.
  final double titleHeight;

  const SeeAllGridMetrics({
    required this.columns,
    required this.childWidth,
    required this.cellHeight,
    required this.titleHeight,
  });

  // Horizontal padding around the grid (24 each side) and the inter-column gap.
  static const double _hPad = 48;
  static const double columnGap = 16;

  /// Gap between rows (SliverGrid mainAxisSpacing).
  static const double rowGap = 20;

  /// Gap between a poster and its title band, inside a cell.
  static const double titleGap = 8;

  /// Padding wrapping the grid, matching [_hPad] horizontally.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(24, 8, 24, 8);

  /// Resolve the geometry for the current width + text scale.
  ///
  /// Android TV renders on a low logical canvas (~960×540 at 2.0 DPR), so a
  /// large target yields only ~4 columns and posters that eat over half the
  /// screen height. Aim for a smaller poster (~130px) → ~6–7 columns and ~2 rows
  /// of comfortably-sized cards, matching how Stremio's own grid reads on a
  /// 10-foot display.
  static SeeAllGridMetrics resolve(
    BuildContext context, {
    required bool isTelevision,
    bool showTitles = true,
  }) {
    final width = MediaQuery.of(context).size.width;
    final target = isTelevision ? 132.0 : 178.0;
    final usable = (width - _hPad).clamp(0.0, double.infinity);
    // TV floor is 4, not 5: the Discover two-pane hands the grid a ~565px
    // panel where 5 forced columns would shrink posters to ~90px; 4 gives the
    // ~117px cards the design wants. Full-width TV canvases still resolve to
    // 5+ columns from the target size, so standalone See-All pages are
    // unaffected.
    final cols = ((usable + columnGap) / (target + columnGap)).floor().clamp(
      isTelevision ? 4 : 3,
      10,
    );
    // Size each cell = a 2:3 poster + a fixed 2-line title band below (matching
    // the board rails and Stremio), sized off the actual column width so the
    // poster stays 2:3 regardless of title length.
    final usableForCell = (width - _hPad).clamp(1.0, double.infinity);
    final childWidth = (usableForCell - (cols - 1) * columnGap) / cols;
    final titleH = showTitles
        ? MediaQuery.textScalerOf(context).scale(13) * 1.3 * 2
        : 0.0;
    final cellH = childWidth * 1.5 + (showTitles ? titleGap + titleH : 0);
    return SeeAllGridMetrics(
      columns: cols,
      childWidth: childWidth,
      cellHeight: cellH,
      titleHeight: titleH,
    );
  }
}

/// A responsive, paginated poster grid shared by every See-All screen (catalog
/// browse, continue watching, Trakt). It owns its focus nodes and scroll
/// controller, walks the grid with the DPAD on TV, and asks for the next page
/// as the user nears the bottom.
///
/// Under a [DiscoverShelfScope] (the Discover STAGE layout) the very same
/// widget lays its items out as ONE bottom shelf instead of a wall: same
/// items, same focus-node pool, same paging — a different arrangement of them.
/// Everything a host configures (exit-top, exit-left, load-more) means the
/// same thing in both, so no caller has to care which is on screen.
///
/// The grid stays presentational — paging state ([loadingMore] / [exhausted])
/// and the item list are owned by the host screen, which calls back through
/// [onLoadMore] and rebuilds with more [items].
class SeeAllPosterGrid extends StatefulWidget {
  final List<StremioMeta> items;
  final bool isTelevision;
  final bool loadingMore;
  final bool exhausted;

  /// Open the detail page for an item (SELECT / tap).
  final void Function(StremioMeta item) onOpen;

  /// Optional long-press / Quick Play straight from the grid.
  final void Function(StremioMeta item)? onQuickPlay;

  /// Fires when a tile gains focus — carries the focused item up to the host
  /// (the Discover two-pane detail rail listens to this).
  final void Function(StremioMeta item)? onItemFocused;

  /// Forwarded to each tile — false drops the MOVIE/SERIES badge. A surrounding
  /// [DiscoverCardSettingsScope] can also turn it off for the whole Discover
  /// surface. Defaults to showing it.
  final bool showTypeBadge;

  /// Forwarded to each tile — false drops the ★-rating chip. A surrounding
  /// [DiscoverCardSettingsScope] can also turn it off for the whole Discover
  /// surface. Defaults to showing it.
  final bool showRatingBadge;

  /// Optional resume progress (0..1) per item — draws the red bar.
  final double? Function(StremioMeta item)? progressOf;

  /// Optional "has a pinned source" flag per item — draws the bookmark badge.
  final bool Function(StremioMeta item)? isBound;

  /// Fetch the next page (host guards against re-entrancy / exhaustion).
  final VoidCallback onLoadMore;

  /// DPAD-up past the first row leaves the grid (e.g. to the filter bar).
  final VoidCallback? onExitTop;

  /// DPAD-left at column 0 leaves the grid (e.g. to the sidebar). No-op if null.
  final VoidCallback? onExitLeft;

  /// SHELF only: DPAD-down leaves the single row (e.g. to the next rail on a
  /// stacked-rails screen). Null keeps the shelf's default of swallowing it.
  final VoidCallback? onExitBottom;

  const SeeAllPosterGrid({
    super.key,
    required this.items,
    required this.isTelevision,
    required this.loadingMore,
    required this.exhausted,
    required this.onOpen,
    required this.onLoadMore,
    this.onQuickPlay,
    this.onItemFocused,
    this.showTypeBadge = true,
    this.showRatingBadge = true,
    this.progressOf,
    this.isBound,
    this.onExitTop,
    this.onExitLeft,
    this.onExitBottom,
  });

  @override
  State<SeeAllPosterGrid> createState() => SeeAllPosterGridState();
}

class SeeAllPosterGridState extends State<SeeAllPosterGrid> {
  final ScrollController _scroll = ScrollController();
  final List<FocusNode> _nodes = [];

  /// Shelf layout (Discover stage) when non-null; the poster wall otherwise.
  /// Read in [didChangeDependencies] so the key handlers — which run outside
  /// build — can branch on it without another context lookup.
  DiscoverShelfMetrics? _shelf;

  /// Which item the DPAD is on, for the shelf's position line. A notifier, not
  /// setState: on TV this changes on every arrow press, and rebuilding the
  /// whole shelf to re-letter one caption is exactly the per-keystroke work
  /// the board layouts avoid.
  final ValueNotifier<int> _focusIndex = ValueNotifier(-1);

  // Distance from the end (px) at which we prefetch the next page. The shelf
  // scrolls sideways through a single row, so its runway is much shorter than
  // the wall's — the same 900px there would prefetch from the first card.
  static const double _loadMoreThreshold = 900;
  static const double _shelfLoadMoreThreshold = 600;

  @override
  void initState() {
    super.initState();
    _syncNodes();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFill());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shelf = DiscoverShelfScope.of(context);
  }

  @override
  void didUpdateWidget(covariant SeeAllPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != _nodes.length) _syncNodes();
    // A reload (filter change) can leave the shelf's remembered position past
    // the end of the new list; follow _syncNodes and fall back to the last
    // surviving card, so re-entry from the filter bar still lands on content.
    if (widget.items.length < oldWidget.items.length &&
        _focusIndex.value >= widget.items.length) {
      _focusIndex.value = widget.items.isEmpty ? -1 : widget.items.length - 1;
    }
    // A short first page (e.g. a niche genre) may not fill the viewport, so no
    // scroll events fire and pagination would stall on non-TV. Keep pulling
    // pages until the content overflows or the catalog is exhausted — the grid's
    // equivalent of the board's _maybeAutoFillBoard.
    if (widget.items.length != oldWidget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFill());
    }
  }

  void _maybeAutoFill() {
    if (!mounted || !_scroll.hasClients) return;
    if (widget.loadingMore || widget.exhausted) return;
    if (_scroll.position.maxScrollExtent <= 0) {
      widget.onLoadMore();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _focusIndex.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _syncNodes() {
    while (_nodes.length < widget.items.length) {
      _nodes.add(FocusNode(debugLabel: 'seeall_grid_${_nodes.length}'));
    }
    // Don't dispose trailing nodes on shrink: this runs in didUpdateWidget,
    // before the build that unmounts the excess tiles, so disposing a node still
    // referenced by a mounted CatalogItemTile.Focus risks a "used after being
    // disposed" assertion. Keep the pool (reused on the next grow; freed en
    // masse in dispose()); just move DPAD focus off any about-to-be-hidden node
    // onto the last still-visible tile so focus isn't stranded.
    if (_nodes.length > widget.items.length) {
      final keep = widget.items.length;
      final focusedHidden = _nodes.skip(keep).any((n) => n.hasFocus);
      if (focusedHidden && keep > 0) {
        _nodes[keep - 1].requestFocus();
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final threshold = _shelf == null
        ? _loadMoreThreshold
        : _shelfLoadMoreThreshold;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - threshold) {
      widget.onLoadMore();
    }
  }

  /// Move DPAD focus back into the results (used when entering from the filter
  /// bar). No-op if there's nothing to focus.
  ///
  /// The SHELF re-enters on the card the user left, not on item 0. Its UP is a
  /// one-press exit from ANY position and doesn't rewind the row, so after a
  /// dozen steps item 0 is far outside the built range — and requestFocus on
  /// an unbuilt tile's detached node is a silent no-op that ALSO latches a
  /// stray focus grab for whenever that tile next mounts (a later reload then
  /// yanks the ring out of the filter bar with no keypress). The filter bar
  /// swallows the key either way, so the visible result is a dead DOWN. The
  /// wall can't hit this: its UP walks row by row, scrolling item 0 back into
  /// view on the way.
  void focusFirst() {
    if (_nodes.isEmpty) return;
    if (_shelf != null) {
      final i = _focusIndex.value;
      if (i >= 0 && i < _nodes.length && _isBuilt(_nodes[i])) {
        _nodes[i].requestFocus();
        return;
      }
      // Nothing remembered, or it went with a reload: rewind so the head is
      // built, then take it on the next frame.
      if (_scroll.hasClients && _scroll.offset > 0) {
        _scroll.jumpTo(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _nodes.isNotEmpty) _nodes.first.requestFocus();
        });
        return;
      }
    }
    _nodes.first.requestFocus();
  }

  /// Whether [node]'s tile is actually mounted — the only state in which
  /// requestFocus does anything.
  bool _isBuilt(FocusNode node) => node.context?.mounted ?? false;

  /// Shelf DPAD: LEFT/RIGHT walk the results, UP leaves for the filter line,
  /// DOWN is swallowed (there is nothing under the shelf, and letting it bubble
  /// hands focus to whatever the app shell has down there). RIGHT at the tail
  /// pulls the next page rather than dead-ending — the shelf's equivalent of
  /// scrolling into the wall's last rows.
  KeyEventResult _handleShelfArrows(int index, KeyEvent event) {
    if (!widget.isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final last = widget.items.length - 1;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _nodes[index - 1].requestFocus();
      } else {
        widget.onExitLeft?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < last) {
        _nodes[index + 1].requestFocus();
        // Prefetch while there's still runway, so the next batch lands before
        // the user arrives rather than after they've stalled at the end.
        if (index + 1 >= last - 2) widget.onLoadMore();
      } else {
        widget.onLoadMore();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onExitTop?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onExitBottom?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleArrows(int index, int cols, KeyEvent event) {
    if (!widget.isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final last = widget.items.length - 1;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index % cols != 0) {
        _nodes[index - 1].requestFocus();
      } else {
        widget.onExitLeft?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index % cols != cols - 1 && index < last) {
        _nodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index >= cols) {
        _nodes[index - cols].requestFocus();
      } else {
        widget.onExitTop?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final target = index + cols;
      if (target <= last) {
        _nodes[target].requestFocus();
        // Prefetch when stepping into the last two rows.
        if (target >= last - cols) widget.onLoadMore();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The STAGE shelf: one row of posters pinned to the bottom of the box the
  /// host gave us, with a position line above it. No per-poster title band —
  /// the identity block on the stage names the focused title at full size, and
  /// a caption under every card would just repeat it smaller.
  Widget _buildShelf(
    DiscoverShelfMetrics m, {
    required bool showTypeBadge,
    required bool showRatingBadge,
  }) {
    final app = AppThemeScope.of(context);
    final items = widget.items;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.hPad),
            child: SizedBox(
              height: DiscoverShelfMetrics.headHeight,
              child: Row(
                children: [
                  if (widget.loadingMore)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          app.seeAll.accent,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Where you are in the list — the sense of place the wall's
                  // second row used to give for free. The total is what's
                  // LOADED, so it wears a "+" until the catalog is exhausted
                  // rather than implying a count nobody knows.
                  ValueListenableBuilder<int>(
                    valueListenable: _focusIndex,
                    builder: (_, i, __) {
                      if (i < 0 || items.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final at = (i + 1).clamp(1, items.length);
                      return Text(
                        '$at / ${items.length}${widget.exhausted ? '' : '+'}',
                        style: TextStyle(
                          color: app.fade(app.core.tx, 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          // This line sits at the far RIGHT of the stage,
                          // where the left column's ink has fully dissolved
                          // and only the bottom ramp's tail is under it —
                          // the one place on this layout where text meets
                          // near-bare artwork. Same tight shadow the plot
                          // uses, for the same reason.
                          shadows: const [
                            Shadow(
                              color: Color(0xBF000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DiscoverShelfMetrics.headGap),
          SizedBox(
            height: m.boxHeight,
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              // ~1.5 cards of lookahead, matching the wall's reasoning: a
              // DPAD target must already be built, since requestFocus on an
              // unbuilt tile's detached node is a silent no-op (dead DPAD).
              cacheExtent: 400,
              padding: EdgeInsets.symmetric(horizontal: m.hPad),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  // Centred in the slack so the board rise's lift isn't
                  // clipped at the viewport's top edge.
                  child: Center(
                    child: SizedBox(
                      width: m.cardWidth,
                      height: m.cardHeight,
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (_, e) => _handleShelfArrows(index, e),
                        child: CatalogItemTile(
                          item: item,
                          isTelevision: widget.isTelevision,
                          focusNode: index < _nodes.length
                              ? _nodes[index]
                              : null,
                          hasBoundSource: widget.isBound?.call(item) ?? false,
                          onOpen: () => widget.onOpen(item),
                          onLongPress: widget.onQuickPlay == null
                              ? null
                              : () => widget.onQuickPlay!(item),
                          onFocused: () {
                            _focusIndex.value = index;
                            widget.onItemFocused?.call(item);
                          },
                          progress: widget.progressOf?.call(item),
                          showInlineTitle: false,
                          showTypeBadge: showTypeBadge,
                          showRatingBadge: showRatingBadge,
                          // Type + rating + watched need about 142px to share
                          // one row. Stage cards max out at 133px, but keep the
                          // threshold explicit if those metrics ever change.
                          compactBadgeLayout: m.cardWidth < 142,
                          // The stage sits beside the Home board and has to
                          // move like it: the board's rise, the board's poster
                          // fade, and a glide instead of a jump.
                          boardChrome: true,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: DiscoverShelfMetrics.tail),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoverSettings = DiscoverCardSettingsScope.maybeOf(context);
    final showTypeBadge =
        widget.showTypeBadge && (discoverSettings?.showTypeTags ?? true);
    final showRatingBadge =
        widget.showRatingBadge && (discoverSettings?.showRatings ?? true);
    final showTitles = discoverSettings?.showTitles ?? true;
    final shelf = _shelf;
    if (shelf != null) {
      return _buildShelf(
        shelf,
        showTypeBadge: showTypeBadge,
        showRatingBadge: showRatingBadge,
      );
    }
    final app = AppThemeScope.of(context);
    final m = SeeAllGridMetrics.resolve(
      context,
      isTelevision: widget.isTelevision,
      showTitles: showTitles,
    );
    final cols = m.columns;
    final titleH = m.titleHeight;
    const titleGap = SeeAllGridMetrics.titleGap;

    return CustomScrollView(
      controller: _scroll,
      // Pre-warm offscreen posters so DPAD scrolling doesn't decode on-screen
      // mid-scroll. ~1.5 rows of lookahead: a DPAD-down target row is always
      // already built (requestFocus on an unbuilt tile's detached node is a
      // silent no-op — dead DPAD), while the old 800px window mounted ~16 extra
      // offscreen tiles on every grid mount, a real slice of the Discover tab's
      // entry cost on TV.
      cacheExtent: widget.isTelevision ? 400 : 250,
      slivers: [
        SliverPadding(
          padding: SeeAllGridMetrics.padding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: m.childWidth / m.cellHeight,
              mainAxisSpacing: SeeAllGridMetrics.rowGap,
              crossAxisSpacing: SeeAllGridMetrics.columnGap,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = widget.items[index];
              return Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, e) => _handleArrows(index, cols, e),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CatalogItemTile(
                        item: item,
                        isTelevision: widget.isTelevision,
                        focusNode: index < _nodes.length ? _nodes[index] : null,
                        hasBoundSource: widget.isBound?.call(item) ?? false,
                        onOpen: () => widget.onOpen(item),
                        onLongPress: widget.onQuickPlay == null
                            ? null
                            : () => widget.onQuickPlay!(item),
                        onFocused: widget.onItemFocused == null
                            ? null
                            : () => widget.onItemFocused!(item),
                        progress: widget.progressOf?.call(item),
                        showInlineTitle: false,
                        showTypeBadge: showTypeBadge,
                        showRatingBadge: showRatingBadge,
                        compactBadgeLayout: m.childWidth < 142,
                      ),
                    ),
                    if (showTitles) ...[
                      const SizedBox(height: titleGap),
                      SizedBox(
                        height: titleH,
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: app.fade(app.core.tx, 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }, childCount: widget.items.length),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: widget.loadingMore ? 72 : 24,
            child: widget.loadingMore
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          app.seeAll.accent,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
