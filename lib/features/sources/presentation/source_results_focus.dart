import 'package:flutter/widgets.dart';

import 'source_row_reveal.dart';

/// Per-view focus coordination. Nodes and scrolling are borrowed from the view;
/// live callbacks preserve decisions made after frames and asynchronous reveals.
class SourceResultsFocus {
  SourceResultsFocus({
    required this.controller,
    required this.readNodes,
    required this.filterFocus,
    required this.pillFocus,
    required this.isMounted,
    required this.searchToken,
    required this.isFrozen,
    required this.hasPendingResults,
    required this.hasSelectedVisible,
    required this.hasRailFocus,
    required this.canRecoverEmpty,
    required this.isTelevision,
    required this.freeze,
    required this.onEvent,
  });

  final ScrollController controller;
  final ValueGetter<List<FocusNode>> readNodes;
  final FocusNode filterFocus;
  final FocusNode pillFocus;
  final ValueGetter<bool> isMounted;
  final ValueGetter<int> searchToken;
  final ValueGetter<bool> isFrozen;
  final ValueGetter<bool> hasPendingResults;
  final ValueGetter<bool> hasSelectedVisible;
  final ValueGetter<bool> hasRailFocus;
  final ValueGetter<bool> canRecoverEmpty;
  final ValueGetter<bool> isTelevision;
  final VoidCallback freeze;
  final void Function(String, Map<String, Object?>) onEvent;

  int _revealRun = 0;
  int _lastCinemaSource = 0;

  void cancelReveal() => ++_revealRun;
  void resetRememberedRow() => _lastCinemaSource = 0;

  void focusRememberedRow() {
    final nodes = readNodes();
    if (nodes.isNotEmpty) {
      nodes[_lastCinemaSource.clamp(0, nodes.length - 1)].requestFocus();
    } else if (filterFocus.context != null) {
      filterFocus.requestFocus();
    }
  }

  bool rememberFocusedRow() {
    final index = readNodes().indexWhere((node) => node.hasFocus);
    if (index >= 0) {
      _lastCinemaSource = index;
      freeze();
    }
    return index >= 0;
  }

  /// Row navigation freezes streaming before selecting a live focus target.
  void rowUp(int index, {required bool redesign}) {
    freeze();
    if (index > 0) {
      readNodes()[index - 1].requestFocus();
    } else if (hasPendingResults()) {
      pillFocus.requestFocus();
    } else if (redesign && isTelevision()) {
      // Classic has no toolbar; only redesigned TV rows reach the funnel.
      filterFocus.requestFocus();
    }
  }

  void rowDown(int index) {
    freeze();
    final nodes = readNodes();
    if (index < nodes.length - 1) nodes[index + 1].requestFocus();
  }

  void pillDown() {
    final nodes = readNodes();
    if (nodes.isNotEmpty) nodes.first.requestFocus();
  }

  bool pillUp() {
    // Classic has no attached toolbar funnel: preserve normal key bubbling.
    if (filterFocus.context == null) return false;
    filterFocus.requestFocus();
    return true;
  }

  void filterDown() {
    if (hasPendingResults()) {
      pillFocus.requestFocus();
    } else {
      pillDown();
    }
  }

  /// The caller resolves row identity before choosing its new position.
  void restoreAfterFrame(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isMounted() && index < readNodes().length) {
        readNodes()[index].requestFocus();
      }
    });
  }

  /// Live TV batches anchor at the top unless the user or a selected pin owns it.
  void anchorStreamingAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() ||
          readNodes().isEmpty ||
          isFrozen() ||
          hasSelectedVisible()) {
        return;
      }
      if (filterFocus.hasFocus || pillFocus.hasFocus || hasRailFocus()) return;
      readNodes().first.requestFocus();
    });
  }

  /// Completion also recovers an empty season/retry view through its filter node.
  void anchorCompletionAfterFrame() {
    if (!isTelevision()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) return;
      if (hasSelectedVisible() ||
          readNodes().any((node) => node.hasFocus) ||
          filterFocus.hasFocus ||
          pillFocus.hasFocus ||
          hasRailFocus()) {
        return;
      }
      if (readNodes().isNotEmpty) {
        readNodes().first.requestFocus();
      } else if (canRecoverEmpty()) {
        filterFocus.requestFocus();
      }
    });
  }

  /// Null means no selected pin; a negative index means that pin is not visible.
  Future<void> reveal(int? index, {bool preserveFocus = false}) async {
    final run = ++_revealRun;
    final token = searchToken();
    if (index == null || index < 0) {
      onEvent('reveal_skipped', {
        'reason': index == null ? 'no_match' : 'match_not_visible',
      });
      return;
    }
    onEvent('reveal_start', const {});
    await revealSourceRow(
      index: index,
      controller: controller,
      readNodes: readNodes,
      canContinue: () =>
          isMounted() &&
          run == _revealRun &&
          token == searchToken() &&
          (preserveFocus || !isFrozen()),
      cancellationReason: () {
        if (!isMounted() ||
            run != _revealRun ||
            token != searchToken() ||
            (!preserveFocus && isFrozen()) ||
            filterFocus.hasFocus ||
            pillFocus.hasFocus ||
            (!preserveFocus && hasRailFocus()) ||
            index >= readNodes().length) {
          return !isMounted()
              ? 'unmounted'
              : run != _revealRun
              ? 'newer_result_batch'
              : token != searchToken()
              ? 'new_search'
              : isFrozen()
              ? 'user_interaction'
              : filterFocus.hasFocus
              ? 'filter_focused'
              : pillFocus.hasFocus
              ? 'new_results_focused'
              : hasRailFocus()
              ? 'sidebar_focused'
              : 'missing_focus_node';
        }
        return null;
      },
      onRowMounted: (node) {
        if (preserveFocus) _lastCinemaSource = index;
        if (isTelevision() && !preserveFocus) node.requestFocus();
      },
      focusRequested: () => isTelevision() && !preserveFocus,
      onEvent: onEvent,
    );
  }
}
