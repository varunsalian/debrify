import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import 'home_stage_rows.dart';

/// Stage rail identity, remembered columns and mounted focus resolution.
/// Rows/nodes are borrowed from the host's current view; this owns no nodes.
class HomeStageNavigation {
  HomeStageNavigation({
    required this.keyOf,
    required this.nodesFor,
    required this.itemsFor,
  });

  final String Function(HomeRail) keyOf;
  final List<FocusNode> Function(HomeRail) nodesFor;
  final List<StremioMeta> Function(HomeRail) itemsFor;
  String? activeKey;
  final columns = <String, int>{};
  bool _seeded = false;

  int resolveIndex(List<HomeRail> rails) {
    final key = activeKey;
    if (key != null) {
      final index = rails.indexWhere((rail) => keyOf(rail) == key);
      if (index >= 0) return index;
    }
    return 0;
  }

  HomeStageRailView? resolveView(List<HomeRail> rails) {
    if (rails.isEmpty) return null;
    final index = resolveIndex(rails);
    final rail = rails[index];
    final key = keyOf(rail);
    // Lock onto the rendered identity before a tracker row can prepend.
    activeKey = key;
    return HomeStageRailView(
      rails: rails,
      index: index,
      rail: rail,
      key: key,
      items: rail.favKind != null ? const <StremioMeta>[] : itemsFor(rail),
      nodes: nodesFor(rail),
    );
  }

  FocusNode? railTarget(List<HomeRail> rails, {String? focusedAtriumKey}) {
    if (rails.isEmpty) return null;
    final activeIndex = resolveIndex(rails);
    var index = activeIndex;
    if (focusedAtriumKey != null) {
      final focused = rails.indexWhere(
        (rail) => keyOf(rail) == focusedAtriumKey,
      );
      // Atrium's focused lower row matters only inside its visible window.
      if (focused == index || focused == index + 1) index = focused;
    }
    final rail = rails[index];
    final node = nearestMountedNode(nodesFor(rail), columns[keyOf(rail)] ?? 0);
    if (node != null) return node;
    // A short board may stop rendering Atrium's second row. Restore the
    // active row instead of leaving the board without a mounted target.
    final active = rails[activeIndex];
    if (identical(active, rail)) return null;
    return nearestMountedNode(nodesFor(active), columns[keyOf(active)] ?? 0);
  }

  /// Move between shelves, or admit a continuation/page at the loaded edge.
  /// Readers stay lazy because continuation focus can synchronously update UI.
  void switchRail({
    required List<HomeRail> rails,
    required int delta,
    required bool Function() rowsPending,
    required bool Function() canAdvance,
    required bool Function() focusContinuation,
    required void Function(String) deferAdvance,
    required VoidCallback loadMore,
    required void Function(String) activate,
    required VoidCallback scheduleFocus,
  }) {
    if (rails.isEmpty) return;
    final current = resolveIndex(rails);
    final next = (current + delta).clamp(0, rails.length - 1);
    if (next == current) {
      if (delta > 0 && !rowsPending() && focusContinuation()) return;
      if (delta > 0 && canAdvance()) {
        // Remember the move before requesting the batch, including sync results.
        deferAdvance(keyOf(rails[current]));
        loadMore();
      } else if (delta > 0) {
        focusContinuation();
      }
      return;
    }
    // Each rail retains its own column; a first visit starts at zero.
    activate(keyOf(rails[next]));
    scheduleFocus();
  }

  void seedFocus({
    required void Function(FocusNode? Function()) schedule,
    required FocusNode? Function() resolveTarget,
  }) {
    if (_seeded) return;
    _seeded = true;
    schedule(() {
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return null;
      return resolveTarget();
    });
  }

  void resetSeed() => _seeded = false;

  /// Search outwards from the remembered column, preferring the lower index
  /// on ties. A detached node must never queue a future, stray focus request.
  static FocusNode? nearestMountedNode(List<FocusNode> nodes, int column) {
    if (nodes.isEmpty) return null;
    bool mounted(FocusNode node) => node.context?.mounted ?? false;
    final current = column.clamp(0, nodes.length - 1);
    if (mounted(nodes[current])) return nodes[current];
    for (var distance = 1; distance < nodes.length; distance++) {
      final lower = current - distance;
      final higher = current + distance;
      if (lower >= 0 && mounted(nodes[lower])) return nodes[lower];
      if (higher < nodes.length && mounted(nodes[higher])) return nodes[higher];
    }
    return null;
  }
}
