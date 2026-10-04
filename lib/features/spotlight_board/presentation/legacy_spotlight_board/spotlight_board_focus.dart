import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpotlightBoardFocus {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardFocus(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  void focusRow(int row, Offset dir, {bool retried = false}) {
    if (row < 0 || row >= view.sections.length) return;
    final nodes = view.sections[row].nodes;
    if (nodes.isEmpty) return;
    final col = (_owners.navigation.col[row] ?? 0).clamp(0, nodes.length - 1);
    bool attached(FocusNode n) => n.context?.mounted ?? false;
    final target = nodes[col];
    if (attached(target)) {
      _sections.movement.go(target, dir);
      return;
    }
    // The remembered column's CELL isn't built — the row is parked at a
    // different offset (its ListView only builds near its own scroll
    // position), or a stale column survived a shelf insert. Focusing a
    // detached node is a silent no-op, which read as "DOWN sometimes does
    // nothing". Land on the nearest BUILT cell instead; the remembered
    // column follows so the next vertical move starts from reality.
    FocusNode? nearest;
    var bestDistance = 1 << 30;
    for (var i = 0; i < nodes.length; i++) {
      final d = (i - col).abs();
      if (d < bestDistance && attached(nodes[i])) {
        bestDistance = d;
        nearest = nodes[i];
        _owners.navigation.col[row] = i;
      }
    }
    if (nearest != null) {
      _sections.movement.go(nearest, dir);
      return;
    }
    // The whole row is outside the lazy build window. Nudge the board's
    // scroll toward it so the builder mounts it, then finish the move next
    // frame — once only, so a row that stays unbuildable can't loop.
    if (retried || !_owners.scroll.scroll.hasClients) return;
    final position = _owners.scroll.scroll.position;
    final step = (dir.dy >= 0 ? 1.0 : -1.0) * 300.0;
    position.moveTo(
      (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deps.mounted()) _sections.focus.focusRow(row, dir, retried: true);
    });
  }

  /// Enter a collection at its selected category, including off-screen rows.
  void focusShelf(int row) {
    if (row < 0 || row >= view.sections.length) return;
    final metrics = _owners.scroll.lastMetrics;
    if (metrics == null || !_owners.scroll.scroll.hasClients) return;
    _deps.setState(() => _owners.navigation.row = row);
    final offset = view.sections
        .take(row)
        .fold<double>(
          0,
          (sum, shelf) => sum + _deps.shelfExtent(shelf, metrics),
        );
    // A lazy list's maximum is only an estimate until distant rows mount.
    // Let layout clamp this exact offset, rather than stopping at that estimate.
    _owners.scroll.scroll.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deps.mounted()) _sections.focus.focusRow(row, const Offset(0, 1));
    });
  }

  /// Where the cursor ACTUALLY is in [nodes].
  ///
  /// `_col` is bookkeeping and can drift — a scroll-into-view, a rebuild, or
  /// anything that moves focus without going through `_walk` leaves it stale.
  /// A stale column is what made LEFT fall through while focus sat mid-row,
  /// handing the key to the shell's geometric search, which then jumped to
  /// whatever row happened to be nearest.
  int liveCol(List<FocusNode> nodes) {
    final i = nodes.indexWhere((n) => n.hasFocus);
    if (i >= 0) return i;
    return (_owners.navigation.col[_owners.navigation.row] ?? 0).clamp(
      0,
      nodes.length - 1,
    );
  }

  /// The shelf that actually holds focus, or -1 for the hero.
  int liveRow() {
    for (var i = 0; i < view.sections.length; i++) {
      if (view.sections[i].nodes.any((n) => n.hasFocus)) return i;
    }
    return -1;
  }

  KeyEventResult onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Re-sync from reality before acting on it.
    final live = _sections.focus.liveRow();
    if (live != _owners.navigation.row) _owners.navigation.row = live;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _sections.movement.down();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _sections.movement.up();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _sections.movement.walk(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
        // The hero was focusable and inert: arrows paged it, but OK did
        // nothing at all, so the reel could be browsed and never opened.
        final item = _sections.heroArt.heroItem;
        final addon = view.heroAddon;
        if (_owners.navigation.row < 0 && item != null && addon != null) {
          _sections.heroArt.openHero();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        // Column 0 and LEFT again falls THROUGH, so the shell's sidebar
        // handler sees it. That is the one and only way in, per the LEFT-only
        // policy — nothing here calls focusTvSidebar.
        //
        // Tested against LIVE focus, not `_col`: falling through from the
        // middle of a row hands the key to a geometric search that lands in
        // another row, which is what made the sidebar hard to reach.
        if (_owners.navigation.row >= 0 &&
            _owners.navigation.row < view.sections.length) {
          final nodes = view.sections[_owners.navigation.row].nodes;
          if (nodes.isEmpty || _sections.focus.liveCol(nodes) == 0) {
            return KeyEventResult.ignored;
          }
        }
        // The hero obeys the same rule as a shelf: at the FIRST item there is
        // nothing to its left but the sidebar. It used to wrap round to the
        // last slide instead, which made the reel a loop with no exit — the
        // one gesture that opens the sidebar was the one gesture it ate.
        if (_owners.navigation.row < 0 &&
            (view.hero.length < 2 || _sections.heroArt.heroIndex == 0)) {
          return KeyEventResult.ignored;
        }
        _sections.movement.walk(-1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Initial entry and re-entry must only target mounted content. Shelves
  /// may arrive before the independently loaded hero, and late hero data
  /// must not move an already placed card cursor.
  FocusNode? focusTarget() {
    bool available(FocusNode node) =>
        (node.context?.mounted ?? false) && node.canRequestFocus;
    if (view.heroNode.hasFocus && available(view.heroNode)) {
      return view.heroNode;
    }
    for (final section in view.sections) {
      for (final node in section.nodes) {
        if (node.hasFocus && available(node)) return node;
      }
    }
    if (_owners.navigation.row >= 0 &&
        _owners.navigation.row < view.sections.length) {
      final nodes = view.sections[_owners.navigation.row].nodes;
      if (nodes.isNotEmpty) {
        final col = (_owners.navigation.col[_owners.navigation.row] ?? 0).clamp(
          0,
          nodes.length - 1,
        );
        if (available(nodes[col])) return nodes[col];
        for (final node in nodes) {
          if (available(node)) return node;
        }
      }
    }
    if (view.hero.isNotEmpty && available(view.heroNode)) {
      return view.heroNode;
    }
    for (final section in view.sections) {
      for (final node in section.nodes) {
        if (available(node)) return node;
      }
    }
    return null;
  }
}
