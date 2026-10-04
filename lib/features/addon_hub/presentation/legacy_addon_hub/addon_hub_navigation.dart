import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AddonHubNavigationDeps = ({
  AddonHubNavigationState navigationState,
  void Function(VoidCallback) setState,
  bool Function() mounted,
  AddonHubEngineState engineState,
  Future<void> Function() loadEngines,
  AddonHubMarketState marketState,
  Future<void> Function(AddonHubSource, {bool force}) loadMarket,
});

class AddonHubNavigation {
  AddonHubNavigation(this._deps);
  final AddonHubNavigationDeps _deps;

  /// Move focus from the filter bar down to the first row of whatever list is
  /// showing (market rows use their own nav pool; installed/engines use the
  /// single first-card node).
  void focusFirstRow() {
    final isMarket =
        _deps.navigationState.kind == AddonHubKind.addons &&
        (_deps.navigationState.source == AddonHubSource.official ||
            _deps.navigationState.source == AddonHubSource.community);
    if (isMarket) {
      _deps.navigationState.marketNav.focus(0);
    } else if (_deps.navigationState.kind == AddonHubKind.addons &&
        _deps.navigationState.source == AddonHubSource.installed &&
        _deps.navigationState.metadataFocus.context != null) {
      _deps.navigationState.metadataFocus.requestFocus();
    } else if (_deps.navigationState.firstRowFocus.context != null) {
      _deps.navigationState.firstRowFocus.requestFocus();
    }
  }

  void toggleSearch() {
    _deps.setState(
      () =>
          _deps.navigationState.searchOpen = !_deps.navigationState.searchOpen,
    );
    if (_deps.navigationState.searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_deps.mounted()) _deps.navigationState.searchFocus.requestFocus();
      });
    } else {
      _deps.navigationState.searchController.clear();
      // Hand focus back to the search button so the remote isn't stranded on a
      // widget that just left the tree.
      _deps.navigationState.searchBtnFocus.requestFocus();
    }
  }

  void selectKind(AddonHubKind kind) {
    if (kind == _deps.navigationState.kind) return;
    _deps.setState(() => _deps.navigationState.kind = kind);
    if (kind == AddonHubKind.engines && !_deps.engineState.enginesLoadedOnce) {
      _deps.loadEngines();
    }
  }

  void selectSource(AddonHubSource source) {
    if (source == _deps.navigationState.source) return;
    _deps.setState(() => _deps.navigationState.source = source);
    if (source != AddonHubSource.installed &&
        _deps.marketState.marketLoadedFor != source) {
      _deps.loadMarket(source);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  /// Page-level DPAD policy. On TV the sidebar shares the screen's focus scope,
  /// so default geometric traversal can "escape" sideways/down into it (focusing
  /// a rail icon pops the sidebar open). The [FocusScope] in [build] contains all
  /// directional moves to this page; this handler then implements the ONE
  /// deliberate exit: a LEFT press that can't move anywhere inside the hub goes
  /// to the sidebar.
  KeyEventResult onPageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    // Let the search field keep left/right for caret movement.
    if (_deps.navigationState.searchFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    // Move within the hub ONLY when there's a focusable genuinely to the left
    // in the same horizontal band (e.g. Configure → Install). We can't lean on
    // focusInDirection's return value here: it's greedy and, from a card's
    // leftmost button (Install), jumps diagonally up to the filter bar and
    // reports moved=true — which would swallow the deliberate LEFT exit to the
    // sidebar. So gate on a real in-band left neighbour instead.
    if (hasLeftNeighbour(primary)) {
      primary.focusInDirection(TraversalDirection.left);
      return KeyEventResult.handled;
    }
    if (MainPageBridge.focusTvSidebar != null) {
      MainPageBridge.focusTvSidebar!();
    }
    return KeyEventResult.handled;
  }

  /// True if any focusable in this scope sits to the LEFT of [primary] while
  /// vertically overlapping its row band — i.e. a real left move exists and
  /// LEFT should stay inside the hub rather than exit to the sidebar.
  bool hasLeftNeighbour(FocusNode primary) {
    final rect = primary.rect;
    final scope = primary.enclosingScope;
    if (scope == null) return false;
    for (final n in scope.traversalDescendants) {
      if (n == primary) continue;
      final r = n.rect;
      final overlapsVertically = r.top < rect.bottom && r.bottom > rect.top;
      if (overlapsVertically && r.center.dx < rect.center.dx - 1) return true;
    }
    return false;
  }
}
