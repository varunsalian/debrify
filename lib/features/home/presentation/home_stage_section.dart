import 'dart:math';
import 'package:flutter/material.dart';
import '../models/home_tonight_card_info.dart';
import 'home_stage_rows.dart';
import 'home_stage_rails.dart';
import 'home_stage_focus_requests.dart';
import 'home_stage_deferred_advance.dart';
import 'home_stage_deferred_right.dart';
import 'home_stage_navigation.dart';
import 'home_stage_theater.dart';
import 'home_stage_hold_latch.dart';
import 'home_tonight_focus.dart';
import 'home_display_section.dart';
import 'home_hero_preview.dart';
import 'home_spotlight_section.dart';

typedef HomeStageDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  VoidCallback clearFavoriteFocus,
  bool Function() rowsPending,
  bool Function() canAdvance,
  bool Function() focusContinuation,
  Future<bool> Function() loadMore,
});

/// Stage rail/zone navigation, deferred focus, hold state and theater lifetime.
class HomeStageSection {
  HomeStageSection(
    this._deps,
    this._rails,
    this._displaySection,
    this._heroPreview,
    this._spotlightSection,
    this._maxDeferredAge,
  );
  final HomeStageDeps _deps;
  final HomeStageRails _rails;
  final HomeDisplaySection _displaySection;
  final HomeHeroPreview _heroPreview;
  final HomeSpotlightSection _spotlightSection;
  final Duration _maxDeferredAge;

  late final HomeStageFocusRequests stageFocusRequests = HomeStageFocusRequests(
    isMounted: () => _deps.mounted(),
    readStyle: () => _displaySection.homeStyleEffective,
  );

  late final HomeStageDeferredAdvance stageDeferredAdvance =
      HomeStageDeferredAdvance(
        stageActive: () => _displaySection.stageActive,
        maxAge: _maxDeferredAge,
      );

  late final HomeStageDeferredRight stageDeferredRight = HomeStageDeferredRight(
    currentRail: () => canvasRailKey,
    stageActive: () => _displaySection.stageActive,
    scheduleFocus: stageFocusRequests.schedule,
    maxAge: _maxDeferredAge,
  );

  void maybeCompleteStageRight() {
    stageDeferredRight.complete((key, column) {
      final rails = _rails.stageRails;
      final i = rails.indexWhere((r) => canvasRailKeyOf(r) == key);
      if (i < 0) return null;
      final nodes = _rails.canvasRailNodes(rails[i]);
      if (column >= nodes.length) return null;
      return (nodes[column].context?.mounted ?? false) ? nodes[column] : null;
    });
  }

  /// Every piece of per-layout navigation state, cleared as one. Called on a
  /// real layout transition (either the picker or the saved pref landing at
  /// cold start) — never partially, or a layout inherits a rail/zone/column
  /// that means something else in its own geometry.
  void resetStageNavigation() {
    stageNavigation.resetSeed();
    stageTheater.reset();
    _deps.clearFavoriteFocus();
    canvasRailKey = null;
    canvasCols.clear();
    tonightFocus.resetPosition();
    atriumFocusedRailKey.value = null;
    tonightCard.value = null;
    stageCol.value = 0;
    stageDeferredAdvance.reset();
    stageDeferredRight.reset();
    stageHold.reset();
    stageFocusRequests.invalidate();
  }

  /// IDENTITY of the active Canvas rail (not an index): rails stream in and
  /// reorder — CW rails prepend when Trakt/Simkl land seconds after a cold
  /// start — and a raw index would silently swap the shelf's content and
  /// teleport focus/hero when that happens. Null = first rail.
  late final stageNavigation = HomeStageNavigation(
    keyOf: canvasRailKeyOf,
    nodesFor: _rails.canvasRailNodes,
    itemsFor: _rails.canvasRailItems,
  );
  String? get canvasRailKey => stageNavigation.activeKey;
  set canvasRailKey(String? key) => stageNavigation.activeKey = key;

  /// The focused column of the active rail, as a notifier — Deck's peek stack
  /// has to re-derive "the next two titles" on every horizontal move, and the
  /// remembered-column MAP is a plain field write that rebuilds nothing.
  final ValueNotifier<int> stageCol = ValueNotifier<int>(0);

  /// Remembered column per rail key (the Canvas mirror of classic's _rowCol).
  Map<String, int> get canvasCols => stageNavigation.columns;

  /// Theater mode: after the ambient trailer has been SHOWING frames for a
  /// dwell, the shelf/tabs (and their bottom scrim) recede so the video owns
  /// the whole screen — logo + AMBIENT chip hold. Any key wakes the lights
  /// (observe-only: the key still does its job), and if playback continues
  /// uninterrupted the dwell re-arms. The shelf is hidden VISUALLY only
  /// (opacity/slide, never unmounted), so focus stays exactly where it was.
  late final HomeStageTheater stageTheater = HomeStageTheater(
    isCurrent: () => _deps.mounted(),
    isEligible: () => _displaySection.theaterEligible,
    isShowing: () => _heroPreview.heroTrailerShowing.value,
    onChanged: () => _deps.setState(() {}),
  );
  bool get canvasTheater => stageTheater.active;

  void onCanvasTrailerShowingChanged() => stageTheater.showingChanged();

  bool onCanvasTheaterKey(KeyEvent event) => stageTheater.handleKey(event);

  String canvasRailKeyOf(HomeRail rail) {
    return 'row:${_rails.canvasRailRowId(rail)}';
  }

  /// Where the active rail currently sits in [rails] — re-resolved every
  /// build so insertions above it never change WHICH rail is shown.
  int resolveCanvasRailIndex(List<HomeRail> rails) =>
      stageNavigation.resolveIndex(rails);

  FocusNode? nearestMountedNode(List<FocusNode> nodes, int col) =>
      HomeStageNavigation.nearestMountedNode(nodes, col);

  /// The displayed Canvas rail's best focus target (sidebar hand-off, tab
  /// re-entry, auto-focus and dead-focus reclaim all route through this via
  /// [_topBoardFocusNode]).
  FocusNode? stageFocusTarget() {
    // Spotlight owns its own cursor — the hero is a focusable row, which the
    // rail-based resolution below cannot describe.
    if (_displaySection.homeStyleEffective == 'spotlight') {
      return _spotlightSection.spotlightKey.currentState?.focusTarget();
    }
    // Tonight parks focus in its vertical queue until the user walks down
    // into the rail zone; the rail resolution below is only right for the
    // rail zone.
    if (_displaySection.homeStyleEffective == 'tonight' && tonightZoneIsQueue) {
      final queue = _rails.tonightQueue;
      if (queue.isNotEmpty) {
        final e = queue[resolveTonightQueueIndex(queue)];
        return nearestMountedNode(e.rail.cw!.nodes, e.col);
      }
    }
    return stageNavigation.railTarget(
      _rails.stageRails,
      focusedAtriumKey: _displaySection.homeStyleEffective == 'atrium'
          ? atriumFocusedRailKey.value
          : null,
    );
  }

  // ── TONIGHT zone state ───────────────────────────────────────────────────

  late final tonightFocus = HomeTonightFocus(
    railKeyOf: canvasRailKeyOf,
    nearestNode: nearestMountedNode,
  );
  bool get tonightZoneIsQueue => tonightFocus.isQueue;
  set tonightZoneIsQueue(bool value) => tonightFocus.isQueue = value;
  ValueNotifier<HomeTonightCardInfo?> get tonightCard => tonightFocus.card;

  final HomeStageHoldLatch stageHold = HomeStageHoldLatch();

  /// UP/DOWN on the shelf: swap which rail the shelf shows — the screen never
  /// scrolls. DOWN past the last loaded rail pulls the next catalog batch;
  /// the new rail becomes reachable when it lands.
  void stageSwitchRail(int delta) {
    stageNavigation.switchRail(
      rails: _rails.stageRails,
      delta: delta,
      rowsPending: () => _deps.rowsPending(),
      canAdvance: () => _deps.canAdvance(),
      focusContinuation: _deps.focusContinuation,
      deferAdvance: stageDeferredAdvance.defer,
      loadMore: _deps.loadMore,
      activate: (nextKey) {
        _deps.setState(() {
          canvasRailKey = nextKey;
          // Re-anchor Atrium's visible window before resolving deferred focus.
          if (_displaySection.homeStyleEffective == 'atrium') {
            atriumFocusedRailKey.value = nextKey;
          }
        });
      },
      scheduleFocus: () => stageFocusRequests.schedule(stageFocusTarget),
    );
  }

  /// A DOWN that ran off the end of the rail list asked for another batch.
  /// Called when one lands: completes the move only if the user is STILL on
  /// the rail they pressed DOWN from, and the request hasn't gone stale — a
  /// late batch must never yank focus out of wherever they went instead.
  void maybeCompleteStageAdvance() {
    late final List<HomeRail> rails;
    late final int i;
    final move = stageDeferredAdvance.take(
      waitingForMore: (key) {
        rails = _rails.stageRails;
        i = rails.indexWhere((r) => canvasRailKeyOf(r) == key);
        return _deps.rowsPending() && i >= 0 && i + 1 >= rails.length;
      },
    );
    if (move == null) return;
    final key = move.railKey;
    final fillLower = move.fillsLower;
    final origin = move.origin;
    if (i < 0 || i + 1 >= rails.length) return;
    // Still where the key was pressed? On Atrium that means the focused ROW,
    // everywhere else the active rail.
    final whereNow = _displaySection.homeStyleEffective == 'atrium'
        ? (atriumFocusedRailKey.value ?? canvasRailKey)
        : canvasRailKey;
    if (whereNow != key) return;
    if (fillLower) {
      // Atrium had only a top row: the window stays put and focus drops into
      // the row that just landed beneath it.
      stageFocusRequests.schedule(() {
        if (!identical(FocusManager.instance.primaryFocus, origin)) return null;
        final now = _rails.stageRails;
        final at = now.indexWhere((r) => canvasRailKeyOf(r) == key);
        if (at < 0 || at + 1 >= now.length) return null;
        final rail = now[at + 1];
        atriumFocusedRailKey.value = canvasRailKeyOf(rail);
        return nearestMountedNode(
          _rails.canvasRailNodes(rail),
          canvasCols[canvasRailKeyOf(rail)] ?? 0,
        );
      });
      return;
    }
    if (_displaySection.homeStyleEffective == 'atrium') {
      // Atrium pressed DOWN from the window's BOTTOM row; its own advance
      // re-resolves the window and lands focus on the new bottom row.
      atriumAdvance(origin: origin);
      return;
    }
    _deps.setState(() => canvasRailKey = canvasRailKeyOf(rails[i + 1]));
    stageFocusRequests.schedule(() {
      if (!(ModalRoute.of(_deps.context())?.isCurrent ?? true)) return null;
      final primary = FocusManager.instance.primaryFocus;
      // Deck/Mosaic replace the entire rail. That intentional replacement
      // detaches the origin before this frame callback and leaves route-scope
      // focus. A different attached card still means the user moved elsewhere.
      final detachedBySwap =
          origin?.parent == null &&
          (primary == null ||
              identical(primary, FocusScope.of(_deps.context())));
      return identical(primary, origin) || detachedBySwap
          ? stageFocusTarget()
          : null;
    });
  }

  /// One-shot: hand entry focus to the active rail the first time a stage
  /// board builds. Shared by every stage layout — the target resolution
  /// ([stageFocusTarget]) already knows which zone owns focus.
  void seedStageFocusOnce() => stageNavigation.seedFocus(
    schedule: stageFocusRequests.schedule,
    resolveTarget: stageFocusTarget,
  );

  /// Every stage board resolves the same four things before painting: the
  /// rails, which one is active, its identity key (persisted so a rail
  /// streaming in above it can't swap the content under the user) and its
  /// nodes. Null means "nothing to show yet" — the caller holds the brand
  /// stage.
  HomeStageRailView? resolveStageRail() =>
      stageNavigation.resolveView(_rails.stageRails);

  /// Which rail currently owns focus in Atrium's two-row wall — drives the
  /// eyebrow above the identity only, so it is a notifier rather than
  /// setState: crossing between the rows must not rebuild the board.
  final ValueNotifier<String?> atriumFocusedRailKey = ValueNotifier<String?>(
    null,
  );

  /// Focus the nearest _deps.mounted() cell of the rail at [index] (its own remembered
  /// column). Both wall rows are _deps.mounted(), so this always has a target.
  void atriumFocusRail(int index) {
    final rails = _rails.stageRails;
    if (index < 0 || index >= rails.length) return;
    final rail = rails[index];
    nearestMountedNode(
      _rails.canvasRailNodes(rail),
      canvasCols[canvasRailKeyOf(rail)] ?? 0,
    )?.requestFocus();
  }

  /// DOWN from the BOTTOM row: scroll the two-row window on by one, so the
  /// row you were on becomes the top row and focus lands on the rail below
  /// it. (Plain [stageSwitchRail] would focus the rail you are already on.)
  void atriumAdvance({FocusNode? origin}) {
    final rails = _rails.stageRails;
    final cur = resolveCanvasRailIndex(rails);
    if (cur + 2 >= rails.length) {
      // Nothing below the bottom row yet — pull the next catalog batch and
      // remember the move so it completes when the rail lands.
      if (_deps.canAdvance()) {
        stageDeferredAdvance.defer(
          canvasRailKeyOf(rails[min(cur + 1, rails.length - 1)]),
        );
        _deps.loadMore();
      }
      return;
    }
    _deps.setState(() => canvasRailKey = canvasRailKeyOf(rails[cur + 1]));
    stageFocusRequests.schedule(() {
      if (_displaySection.homeStyleEffective != 'atrium') return null;
      // Deferred completions pass the node that pressed DOWN; focus can move
      // during the frame gap, and a late batch must not yank it back.
      if (origin != null &&
          !identical(FocusManager.instance.primaryFocus, origin)) {
        return null;
      }
      // After the shift the window is [cur+1, cur+2]; land on its bottom row.
      final rails = _rails.stageRails;
      final i = resolveCanvasRailIndex(rails) + 1;
      if (i >= rails.length) return null;
      final rail = rails[i];
      atriumFocusedRailKey.value = canvasRailKeyOf(rail);
      return nearestMountedNode(
        _rails.canvasRailNodes(rail),
        canvasCols[canvasRailKeyOf(rail)] ?? 0,
      );
    });
  }

  int resolveTonightQueueIndex(List<HomeTonightQueueEntry> queue) =>
      tonightFocus.resolveIndex(queue);

  bool tonightFocusQueue() => tonightFocus.focusQueue(_rails.tonightQueue);

  bool tonightFocusRail() {
    final node = () {
      final rails = _rails.stageRails;
      if (rails.isEmpty) return null;
      final rail = rails[resolveCanvasRailIndex(rails)];
      return nearestMountedNode(
        _rails.canvasRailNodes(rail),
        canvasCols[canvasRailKeyOf(rail)] ?? 0,
      );
    }();
    return tonightFocus.focusRail(node);
  }
}
