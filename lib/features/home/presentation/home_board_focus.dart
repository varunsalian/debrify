import 'package:flutter/material.dart';
import '../../discover/presentation/discover_section.dart';
import '../../search/presentation/search_input_section.dart';
import '../../search/presentation/lists_search_section.dart';
import 'home_board_section.dart';
import 'home_classic_navigation.dart';
import 'home_continuation_focus.dart';
import 'home_continuation_section.dart';
import 'home_saved_content_section.dart';
import 'home_display_section.dart';
import 'home_stage_section.dart';
import 'home_stage_rails.dart';
import 'home_spotlight_section.dart';
import 'home_hero_preview.dart';

typedef HomeBoardFocusDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  int Function() activeTabIndex,
  int Function() tabIndex,
  bool Function() sidebarFocused,
  VoidCallback focusSidebar,
  Future<bool> Function() loadMore,
  VoidCallback maybeCompleteDeferredDown,
  void Function({int rowIndex, String? homeRowId, required int column})
  deferDownMove,
});

/// Board focus entry, idle auto-placement, reclaim and classic rail navigation.
class HomeBoardFocus {
  HomeBoardFocus(
    this._deps,
    this._boardSection,
    this._inputSection,
    this._discoverSection,
    this._listsSection,
    this._continuationSection,
    this._savedSection,
    this._displaySection,
    this._stageSection,
    this._stageRailsSection,
    this._spotlightSection,
    this._heroPreview,
  );
  final HomeBoardFocusDeps _deps;
  final HomeBoardSection _boardSection;
  final SearchInputSection _inputSection;
  final DiscoverSection _discoverSection;
  final ListsSearchSection _listsSection;
  final HomeContinuationSection _continuationSection;
  final HomeSavedContentSection _savedSection;
  final HomeDisplaySection _displaySection;
  final HomeStageSection _stageSection;
  final HomeStageRails _stageRailsSection;
  final HomeSpotlightSection _spotlightSection;
  final HomeHeroPreview _heroPreview;

  final catalogFocus = HomeContinuationFocus();
  FocusNode get catalogContinueNode => catalogFocus.continueNode;
  FocusNode get catalogMoreNode => catalogFocus.moreNode;

  /// TV auto-focus "settle to the top" state. On arrival the board focuses the
  /// best card available immediately (an addon row if the Trakt rows above it
  /// are still loading), remembering that node in [_autoFocusedNode]. As higher
  /// rows load (Trakt, local Continue Watching), focus slides up to the new top
  /// card — but only while the user is idle (focus still sits on the node we
  /// placed). The instant the user moves focus themselves, [autoFocusSettled]
  /// latches and we never touch focus again.
  FocusNode? _autoFocusedNode;
  bool autoFocusSettled = false;

  /// Coalesces auto-focus passes: multiple content loads finishing in one frame
  /// schedule a single post-frame placement (which reads the final top after all
  /// their setStates apply), instead of racing several callbacks whose
  /// primaryFocus reads haven't caught up to each other's requestFocus.
  bool _autoFocusScheduled = false;

  /// Place — or re-anchor — the board's auto-focus after content loads, so
  /// arriving on the Home tab lands on a card (no stray arrow press) and then
  /// *settles to the top*: focus the best card available now, and as higher rows
  /// arrive (Trakt filling its reserved slot, local Continue Watching) slide up
  /// to the new top card while the user is idle. See [_autoFocusedNode] /
  /// [autoFocusSettled] for the state machine.
  ///
  /// TV-only, homepage board only. Deferred a frame so the target row is mounted.
  void maybeAutoFocusBoard() {
    // Every row-load settle path funnels through here, which makes it the one
    // hook needed to complete a DPAD-down deferred while that row was loading.
    // Runs before the settle latch below — deferred moves are USER presses and
    // must work long after auto-focus has handed over control.
    _deps.maybeCompleteDeferredDown();
    if (autoFocusSettled || _autoFocusScheduled) return;
    if (!_deps.isTelevision()) return;
    if (_deps.searchMode() || _deps.discoverMode()) return;
    _autoFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Coalesced pass: reads the final top after every same-frame load's
      // setState has applied, so multiple loads don't race.
      _autoFocusScheduled = false;
      if (!_deps.mounted() || autoFocusSettled) return;
      if (_deps.searchMode() || _deps.discoverMode()) return;
      // Only when this is the tab the user is actually looking at. During the
      // ~350ms tab cross-fade the outgoing board is still mounted and shares the
      // ModalRoute, so isCurrent can't tell them apart — the active-tab index
      // can. (main.dart keeps it in lock-step with the rendered tab.)
      if (_deps.activeTabIndex() != _deps.tabIndex()) return;
      // Don't grab focus if the board isn't the top route — e.g. the user
      // opened a detail page or player and a slow CW/Trakt load only just
      // finished. Stealing focus here would yank it off the pushed screen onto
      // the hidden board below.
      final route = ModalRoute.of(_deps.context());
      if (route != null && !route.isCurrent) return;
      if (_deps.sidebarFocused()) return;

      final primary = FocusManager.instance.primaryFocus;
      final boardFocused = boardHasFocus();
      if (_autoFocusedNode == null) {
        // Never placed focus yet. If the user already reached a board card on
        // their own, leave it and latch — nothing to auto-place.
        if (boardFocused) {
          autoFocusSettled = true;
          return;
        }
      } else if (boardFocused && primary != _autoFocusedNode) {
        // We placed focus earlier and it now sits on a *different* board card —
        // the user has taken control. Stop re-anchoring so we never fight them.
        // (Guarded by boardFocused so our own just-applied requestFocus, or a
        // transient null primaryFocus between loads, can't false-trigger this.)
        autoFocusSettled = true;
        return;
      }

      final top = topBoardFocusNode();
      if (top == null) return; // nothing focusable yet — retry on the next load
      if (top == _autoFocusedNode) {
        return; // already anchored to the current top
      }
      top.requestFocus();
      _autoFocusedNode = top;
    });
  }

  /// Whether any focusable element on this screen currently holds focus. Used to
  /// avoid stealing focus from the user in [maybeAutoFocusBoard].
  bool boardHasFocus() {
    bool anyOf(List<FocusNode> ns) => ns.any((n) => n.hasFocus);
    if (_inputSection.searchFocus.hasFocus ||
        _discoverSection.discSourceNode.hasFocus ||
        // Spotlight's hero is a focus target the rail lists know nothing
        // about; without this the arrival machinery thinks the board is
        // unfocused while the hero holds the cursor and steals it back.
        _spotlightSection.spotlightHeroNode.hasFocus) {
      return true;
    }
    if (anyOf(_listsSection.listsNodes)) return true;
    if (anyOf(_continuationSection.cwMovieNodes) ||
        anyOf(_continuationSection.cwSeriesNodes) ||
        anyOf(_continuationSection.traktMovieNodes) ||
        anyOf(_continuationSection.traktSeriesNodes) ||
        anyOf(_continuationSection.simklMovieNodes) ||
        anyOf(_continuationSection.simklSeriesNodes) ||
        anyOf(_continuationSection.mdblistMovieNodes) ||
        anyOf(_continuationSection.mdblistSeriesNodes) ||
        anyOf(_savedSection.tvFavNodes) ||
        anyOf(_savedSection.stvFavNodes) ||
        anyOf(_savedSection.iptvFavNodes) ||
        anyOf(_savedSection.watchlistMovieNodes) ||
        anyOf(_savedSection.watchlistSeriesNodes) ||
        anyOf(_savedSection.playlistFavNodes)) {
      return true;
    }
    for (final row in _boardSection.rowNodes) {
      if (anyOf(row)) return true;
    }
    return false;
  }

  /// The focus node for the board's current top card — the same target
  /// [_inputSection.focusContent] would pick on the board path (Continue Watching →
  /// favourites → catalog rows), or null if nothing is focusable yet. Skeleton
  /// Trakt rows carry no nodes, so they're naturally skipped: while Trakt is
  /// reserving, the top is whatever real row sits below the skeletons, and once
  /// the real Trakt rows land they become the top. Drives the "settle to the
  /// top" re-anchor in [maybeAutoFocusBoard].
  FocusNode? topBoardFocusNode() {
    // Canvas shows exactly ONE rail — the classic top-row targets are
    // usually unmounted there (and requestFocus on a detached node only
    // latches a stray later grab), so sidebar hand-off / tab re-entry /
    // auto-focus all aim at the displayed rail's nearest mounted cell.
    // Canvas renders exactly ONE rail, so aim at its nearest mounted cell;
    // null (rails still loading) falls through to the classic targets.
    if (_displaySection.stageActive) return _stageSection.stageFocusTarget();
    for (final rail in _stageRailsSection.canvasRails) {
      final nodes = _stageRailsSection.canvasRailNodes(rail);
      if (nodes.isNotEmpty) return nodes.first;
    }
    return null;
  }

  bool _focusReclaimScheduled = false;

  /// FocusManager listener (TV board only): fires on every app-wide focus
  /// change, so the common path must bail out in a comparison or two. Only a
  /// DEAD state — primary focus fell back to a bare scope (the focused node
  /// was disposed) — schedules the post-frame reclaim pass.
  void onGlobalFocusChange() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    if (_focusReclaimScheduled) return;
    _focusReclaimScheduled = true;
    // Post-frame: the disposal that killed focus is usually mid-rebuild; the
    // board's surviving cells are attached again by the frame's end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusReclaimScheduled = false;
      reclaimDeadFocus();
    });
  }

  /// Re-anchor focus onto the board after it died. Deliberately picks the
  /// first MOUNTED cell (Continue Watching → favourites → catalog order) — if
  /// the user was deep in the board, the top rows' cells are unmounted and
  /// requestFocus on them is a silent no-op, so walking to a mounted node also
  /// lands focus near where they were looking.
  void reclaimDeadFocus() {
    if (!_deps.mounted()) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return; // recovered
    if (_deps.activeTabIndex() != _deps.tabIndex()) return;
    final route = ModalRoute.of(_deps.context());
    if (route != null && !route.isCurrent) return;
    if (_deps.sidebarFocused()) return;

    // On a stage layout only ONE rail (and, on Tonight, one zone) is mounted,
    // so the data-order walk below would land wherever the first mounted node
    // happens to be — a different rail, or the wrong Tonight zone with the
    // zone flag left lying. Ask the layout where focus belongs first.
    if (_displaySection.stageActive) {
      final target = _stageSection.stageFocusTarget();
      if (target != null && (target.context?.mounted ?? false)) {
        target.requestFocus();
        return;
      }
    }

    bool tryRow(List<FocusNode> nodes) {
      for (final n in nodes) {
        if (n.context?.mounted ?? false) {
          n.requestFocus();
          return true;
        }
      }
      return false;
    }

    for (final rail in _stageRailsSection.canvasRails) {
      if (tryRow(_stageRailsSection.canvasRailNodes(rail))) return;
    }
  }

  /// DPAD-up from the top row. On the dedicated Search tab the field sits above
  /// the results, so land there; on the Home-New board there's nothing above —
  /// stay put. (This used to hand focus to the sidebar, but the sidebar policy
  /// is now LEFT-only: no other direction may open it.)
  void leaveBoardTop() {
    _heroPreview.heroPreviewPolicy.resetAttempt();
    if (_deps.searchMode()) {
      _inputSection.searchFocusNode.requestFocus();
    }
  }

  /// Returns false when the target catalog row isn't loaded/focusable (after
  /// kicking the next batch load if one is available) — same contract as
  /// [_continuationMenu.focusCwRow], so DPAD wiring can defer the move instead of eating it.
  bool focusRow(int row, int column) {
    if (row >= _boardSection.rowNodes.length) {
      // Reach visible actions before starting another batch. When no action
      // is mounted, retain the existing deferred move into the next row.
      if (!_boardSection.boardLoadingMore && focusCatalogContinuation()) {
        return true;
      }
      if (_boardSection.boardHasMore) _deps.loadMore();
      return false;
    }
    if (row < 0) return false;
    final nodes = _boardSection.rowNodes[row];
    if (nodes.isEmpty) return false;
    // Land on the row's own remembered column, not the source column, so
    // returning to a row you'd scrolled right goes back where you left it (that
    // cell is still mounted). First visit falls back to the incoming column.
    final desired = (_boardSection.rowCol[row] ?? column).clamp(
      0,
      nodes.length - 1,
    );
    requestRowFocus(nodes, desired);
    return true;
  }

  void requestRowFocus(List<FocusNode> nodes, int desired) => _boardSection
      .boardViewport
      .requestFocus(nodes, desired, isCurrent: () => _deps.mounted());

  late final _classicNavigation = HomeClassicNavigation(
    rails: () => _stageRailsSection.canvasRails,
    rowIdOf: _stageRailsSection.canvasRailRowId,
    nodesFor: _stageRailsSection.canvasRailNodes,
    requestFocus: requestRowFocus,
    leaveTop: leaveBoardTop,
    loadingMore: () => _boardSection.boardLoadingMore,
    hasMore: () => _boardSection.boardHasMore,
    focusContinuation: focusCatalogContinuation,
    loadMore: _deps.loadMore,
    deferDown: (rowId, column) =>
        _deps.deferDownMove(homeRowId: rowId, column: column),
  );

  bool focusHomeRailAt(int index, int column) =>
      _classicNavigation.focusAt(index, column);

  void focusRelativeHomeRail(String rowId, int delta, int column) =>
      _classicNavigation.move(rowId, delta, column);

  bool focusCatalogContinuation() => catalogFocus.focusAction();

  void restoreCatalogContinuationFocus() {
    if (catalogFocus.restore([
      _stageSection.stageFocusTarget(),
      for (final rail in _stageRailsSection.canvasRails)
        ..._stageRailsSection.canvasRailNodes(rail),
    ])) {
      return;
    }
    _deps.focusSidebar();
  }

  /// Await the initial board content loads, then end the auto-focus "arrival
  /// window": one final placement pass, then latch [autoFocusSettled] so
  /// re-anchoring never fires again (a background CW/Trakt refresh, or focus
  /// restoration after returning from playback, must not move the user's focus).
  Future<void> settleAutoFocusAfter(List<Future<void>> loads) async {
    await Future.wait(loads.map((f) => f.catchError((_) {})));
    if (!_deps.mounted()) return;
    maybeAutoFocusBoard();
    // Latch on the following frame so the placement pass above runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deps.mounted()) autoFocusSettled = true;
    });
  }
}
