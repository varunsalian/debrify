import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

// ── movement ───────────────────────────────────────────────────────────

class SpotlightBoardMovement {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardMovement(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  void go(FocusNode node, Offset dir) {
    ParallaxTravel.note(dir);
    node.requestFocus();
  }

  void page(int delta) {
    if (view.hero.length < 2) return;
    final n = view.hero.length;
    final next = (_sections.heroArt.heroIndex + delta + n) % n;
    if (view.hero[next].id == _owners.hero.heroId) return;
    _sections.cadence.stopRolling();
    _owners.hero.dwelledHeroId = null;
    _deps.setState(() => _owners.hero.heroId = view.hero[next].id);
    view.refreshMetadataPresentation();
    ParallaxTravel.note(Offset(delta.toDouble(), 0));
    _sections.ambient.probe();
    _sections.cadence.restartCadence();
  }

  void finishProgressiveDown() {
    if (_owners.navigation.pendingProgressiveDown == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = _owners.navigation.pendingProgressiveDown;
      if (!_deps.mounted() || pending == null) return;
      if (!(ModalRoute.isCurrentOf(_deps.context()) ?? true) ||
          !identical(FocusManager.instance.primaryFocus, pending.origin) ||
          DateTime.now().difference(pending.at) > const Duration(seconds: 3)) {
        _owners.navigation.pendingProgressiveDown = null;
        return;
      }
      final row = view.sections.indexWhere(
        (s) => s.nodes.contains(pending.origin),
      );
      if (row < 0 || row + 1 >= view.sections.length) {
        if (!view.pendingShelves) {
          _owners.navigation.pendingProgressiveDown = null;
        }
        return;
      }
      _owners.navigation.pendingProgressiveDown = null;
      _deps.setState(() => _owners.navigation.row = row + 1);
      _sections.focus.focusRow(_owners.navigation.row, const Offset(0, 1));
    });
  }

  Future<void> loadShelvesAndFinishDown() async {
    final load = view.onLoadMoreShelves;
    if (load == null || _owners.navigation.loadingMoreShelves) return;

    final origin = FocusManager.instance.primaryFocus;
    final oldLength = view.sections.length;
    _deps.setState(() => _owners.navigation.loadingMoreShelves = true);

    var appended = false;
    try {
      appended = await load();
    } catch (_) {
      // A catalog failure is recoverable: leave focus where it was so another
      // DOWN can retry, and always remove the loading acknowledgement below.
    }
    if (!_deps.mounted()) return;
    _deps.setState(() => _owners.navigation.loadingMoreShelves = false);
    if (!appended) {
      if (view.pendingShelves && origin != null) {
        _owners.navigation.pendingProgressiveDown = (
          origin: origin,
          at: DateTime.now(),
        );
        _sections.movement.finishProgressiveDown();
      }
      return;
    }

    // The host's setState that appended the shelves mounts their focus nodes
    // on the next frame. Complete the original DOWN only if the user is still
    // on the exact card that requested it; a slow addon must never pull focus
    // back after they moved sideways or opened the sidebar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || view.sections.length <= oldLength) return;
      // Inserting a leading shelf reuses the positional shelf elements and can
      // briefly detach [origin], leaving primaryFocus null. That is safe to
      // recover. A different focused node means the user deliberately moved;
      // a different route means they opened content while the addon loaded.
      final primary = FocusManager.instance.primaryFocus;
      if ((primary != null && !identical(primary, origin)) ||
          !(ModalRoute.of(_deps.context())?.isCurrent ?? true)) {
        return;
      }
      // Continue Watching and favourites resolve independently and can insert
      // shelves at the front while the catalog request is in flight. Find the
      // origin by its stable FocusNode after the rebuild instead of assuming
      // the old list length is still the appended shelf's index.
      final currentRow = view.sections.indexWhere(
        (section) => section.nodes.contains(origin),
      );
      if (currentRow < 0 || currentRow + 1 >= view.sections.length) return;
      _deps.setState(() => _owners.navigation.row = currentRow + 1);
      _sections.focus.focusRow(_owners.navigation.row, const Offset(0, 1));
    });
  }

  /// Touch has no focused last shelf to retain while a batch loads. It still
  /// uses the same in-flight guard as DPAD, but deliberately leaves focus
  /// alone when the host appends the new shelves.
  Future<void> loadMoreShelvesForTouch() async {
    final load = view.onLoadMoreShelves;
    if (view.dpad || load == null || _owners.navigation.loadingMoreShelves) {
      return;
    }

    _deps.setState(() => _owners.navigation.loadingMoreShelves = true);
    try {
      await load();
    } catch (_) {
      // A later scroll can retry a recoverable catalog failure.
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() => _owners.navigation.loadingMoreShelves = false);
      }
    }
  }

  void down() {
    if (_owners.navigation.row < 0) {
      if (view.sections.isEmpty) return;
      _sections.cadence.stopRolling();
      _deps.setState(() => _owners.navigation.row = 0);
      _owners.hero.cadence?.cancel();
      _sections.focus.focusRow(0, const Offset(0, 1));
      return;
    }
    if (_owners.navigation.row + 1 >= view.sections.length) {
      // Out of shelves: retain this DOWN while the next batch loads. When it
      // lands, focus advances into its first shelf without a second keypress.
      unawaited(_sections.movement.loadShelvesAndFinishDown());
      return;
    }
    _deps.setState(() => _owners.navigation.row = _owners.navigation.row + 1);
    _sections.focus.focusRow(_owners.navigation.row, const Offset(0, 1));
  }

  void up() {
    if (_owners.navigation.row <= 0) {
      if (view.shelvesOnly) {
        view.onExitTop?.call();
        return;
      }
      // Local shelves can precede hero data. Do not leave a pending focus
      // request that steals the cursor when the hero eventually mounts.
      if (view.hero.isEmpty || !(view.heroNode.context?.mounted ?? false)) {
        return;
      }
      _deps.setState(() => _owners.navigation.row = -1);
      _sections.cadence.restartCadence();
      _sections.movement.go(view.heroNode, const Offset(0, -1));
      _owners.scroll.scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _deps.setState(() => _owners.navigation.row = _owners.navigation.row - 1);
    _sections.focus.focusRow(_owners.navigation.row, const Offset(0, -1));
  }

  void walk(int delta) {
    if (_owners.navigation.row < 0 ||
        _owners.navigation.row >= view.sections.length) {
      _sections.movement.page(delta);
      return;
    }
    final nodes = view.sections[_owners.navigation.row].nodes;
    if (nodes.isEmpty) return;
    final at = _sections.focus.liveCol(nodes);
    final next = at + delta;
    if (view.shelvesOnly && delta > 0 && next >= nodes.length) {
      view.onLoadMoreRow?.call(_owners.navigation.row);
    }
    if (next < 0 || next >= nodes.length) return;
    // No setState: a horizontal step changes nothing this board PAINTS —
    // the cursor's visuals live inside each cell's own Focus widget, and
    // `_col` is read only by the focus-targeting helpers. Wrapped in
    // setState it rebuilt the hero stack and every shelf shell on every
    // LEFT/RIGHT of a held key — per-keypress cost a MiBox-class CPU
    // renders as visible lag.
    _owners.navigation.col[_owners.navigation.row] = next;
    _sections.movement.go(nodes[next], Offset(delta.toDouble(), 0));
    // Four from the end is roughly one screen of posters — enough lead time
    // for a page to land before the cursor reaches where it would have
    // stopped.
    if (next >= nodes.length - 4) {
      view.onLoadMoreRow?.call(_owners.navigation.row);
    }
  }
}
