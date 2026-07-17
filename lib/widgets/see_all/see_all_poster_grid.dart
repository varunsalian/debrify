import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../catalog_item_tile.dart';
import 'see_all_theme.dart';

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
  }) {
    final width = MediaQuery.of(context).size.width;
    final target = isTelevision ? 132.0 : 178.0;
    final usable = (width - _hPad).clamp(0.0, double.infinity);
    final cols = ((usable + columnGap) / (target + columnGap))
        .floor()
        .clamp(isTelevision ? 5 : 3, 10);
    // Size each cell = a 2:3 poster + a fixed 2-line title band below (matching
    // the board rails and Stremio), sized off the actual column width so the
    // poster stays 2:3 regardless of title length.
    final usableForCell = (width - _hPad).clamp(1.0, double.infinity);
    final childWidth = (usableForCell - (cols - 1) * columnGap) / cols;
    final titleH = MediaQuery.textScalerOf(context).scale(13) * 1.3 * 2;
    final cellH = childWidth * 1.5 + titleGap + titleH;
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

  /// Forwarded to each tile — false drops the MOVIE/SERIES badge (Discover TV,
  /// where the detail rail already names the type). Defaults to showing it.
  final bool showTypeBadge;

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
    this.progressOf,
    this.isBound,
    this.onExitTop,
    this.onExitLeft,
  });

  @override
  State<SeeAllPosterGrid> createState() => SeeAllPosterGridState();
}

class SeeAllPosterGridState extends State<SeeAllPosterGrid> {
  final ScrollController _scroll = ScrollController();
  final List<FocusNode> _nodes = [];

  // Distance from the bottom (px) at which we prefetch the next page.
  static const double _loadMoreThreshold = 900;

  @override
  void initState() {
    super.initState();
    _syncNodes();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFill());
  }

  @override
  void didUpdateWidget(covariant SeeAllPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != _nodes.length) _syncNodes();
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
      final focusedHidden =
          _nodes.skip(keep).any((n) => n.hasFocus);
      if (focusedHidden && keep > 0) {
        _nodes[keep - 1].requestFocus();
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - _loadMoreThreshold) {
      widget.onLoadMore();
    }
  }

  /// Move DPAD focus onto the first tile (used when entering from the filter
  /// bar). No-op if the grid is empty.
  void focusFirst() {
    if (_nodes.isNotEmpty) _nodes.first.requestFocus();
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

  @override
  Widget build(BuildContext context) {
    final m = SeeAllGridMetrics.resolve(context, isTelevision: widget.isTelevision);
    final cols = m.columns;
    final titleH = m.titleHeight;
    const titleGap = SeeAllGridMetrics.titleGap;

    return CustomScrollView(
      controller: _scroll,
      // Pre-warm offscreen posters so DPAD scrolling doesn't decode on-screen
      // mid-scroll (matches the board's cacheExtent).
      cacheExtent: widget.isTelevision ? 800 : 250,
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
            delegate: SliverChildBuilderDelegate(
              (context, index) {
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
                          focusNode:
                              index < _nodes.length ? _nodes[index] : null,
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
                          showTypeBadge: widget.showTypeBadge,
                        ),
                      ),
                      const SizedBox(height: titleGap),
                      SizedBox(
                        height: titleH,
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: widget.items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: widget.loadingMore ? 72 : 24,
            child: widget.loadingMore
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(kSeeAllAccent),
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
