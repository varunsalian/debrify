import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/home/home_row_focus.dart';

/// Board scroll and catalog-row focus resources. Scroll initialization and the
/// two disposal phases are explicit to preserve the host's lifecycle ordering.
class HomeBoardViewport {
  late final ScrollController scroll;
  final nodes = <List<FocusNode>>[];
  final columns = <int, int>{};

  void initializeScroll(double offset) {
    scroll = ScrollController(initialScrollOffset: offset);
  }

  void appendRows(List<CatalogSection> sections) {
    for (final section in sections) {
      nodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(debugLabel: 'search_r${nodes.length}_c$i'),
        ),
      );
    }
  }

  void appendItems(int row, int count) {
    final rowNodes = nodes[row];
    final base = rowNodes.length;
    for (var i = 0; i < count; i++) {
      rowNodes.add(FocusNode(debugLabel: 'search_r${row}_c${base + i}'));
    }
  }

  void replaceRows({
    required List<CatalogSection> previous,
    required List<CatalogSection> next,
    required String Function(CatalogSection) rowId,
    required bool preserveFocus,
    required bool incremental,
  }) {
    if (!preserveFocus) {
      disposeNodes();
      appendRows(next);
      return;
    }
    List<List<String>> identities(List<CatalogSection> rows) => [
      for (final row in rows)
        [
          for (final item in row.items)
            jsonEncode([rowId(row), item.type, item.id]),
        ],
    ];
    final nextNodes = reconcileHomeRowFocus(
      previousIds: identities(previous),
      previousNodes: nodes,
      nextIds: identities(next),
    );
    final remembered = {
      if (incremental)
        for (var i = 0; i < previous.length; i++)
          rowId(previous[i]): columns[i],
    };
    nodes
      ..clear()
      ..addAll(nextNodes);
    columns
      ..clear()
      ..addAll({
        for (var i = 0; i < next.length; i++)
          if (remembered[rowId(next[i])] case final column?) i: column,
      });
  }

  void disposeScroll() => scroll.dispose();

  void disposeNodes() {
    for (final row in nodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    nodes.clear();
    // Replaced numeric indices must not retain another row's column memory.
    columns.clear();
  }

  /// Focus [desired] in [nodes] if its cell is mounted; otherwise the nearest
  /// mounted cell. A horizontal ListView.builder unmounts off-screen cells, and
  /// requestFocus() on an unmounted FocusNode is a silent no-op — so a naive
  /// nodes[desired].requestFocus() leaves focus stranded on the previous row.
  void requestFocus(
    List<FocusNode> nodes,
    int desired, {
    required bool Function() isCurrent,
    int hops = 0,
  }) {
    // NB: FocusNode.context stays non-null after the owning Focus unmounts
    // (detach() doesn't clear it), so the element's own `mounted` flag — which
    // flips false on unmount — is the reliable "can this node take focus" test.
    bool isMounted(FocusNode n) => n.context?.mounted ?? false;
    if (isMounted(nodes[desired])) {
      nodes[desired].requestFocus();
      return;
    }
    for (var d = 1; d < nodes.length; d++) {
      final lo = desired - d;
      final hi = desired + d;
      if (lo >= 0 && isMounted(nodes[lo])) {
        nodes[lo].requestFocus();
        return;
      }
      if (hi < nodes.length && isMounted(nodes[hi])) {
        nodes[hi].requestFocus();
        return;
      }
    }
    // The whole row is unmounted: it sits beyond the board's deliberately
    // small vertical cacheExtent (300) — the live case is DPAD-down off the
    // last Continue Watching row while TWO Trakt skeleton rows (~380px of
    // focusless shimmer) separate it from the favourites/catalog row below.
    // requestFocus on a detached node would only latch a focus grab for
    // whenever that cell happens to build (a later yank, not a move — the old
    // "blocked DOWN"), so instead nudge the board forward and retry until the
    // row builds. Down-only on purpose: an unmounted target ABOVE can't
    // happen from row-by-row DPAD moves (the row above was just on screen,
    // still inside the cache). Bounded so the total travel stays within the
    // cache above the origin cell — it can't unmount mid-journey — and a
    // settled miss just leaves focus where it was.
    //
    // Glides (was jumpTo — a visible 45%-viewport teleport). The retry MUST
    // wait for the glide to land, not the next frame: per-frame retries would
    // spend all 3 hops inside one animation before the row could ever build.
    if (hops >= 3 || !scroll.hasClients) return;
    final pos = scroll.position;
    if (pos.pixels >= pos.maxScrollExtent) return;
    scroll
        .animateTo(
          (pos.pixels + pos.viewportDimension * 0.45).clamp(
            0.0,
            pos.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (isCurrent()) {
              requestFocus(
                nodes,
                desired,
                isCurrent: isCurrent,
                hops: hops + 1,
              );
            }
          });
        });
  }
}
