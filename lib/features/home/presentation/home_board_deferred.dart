import 'package:flutter/material.dart';
import 'home_board_section.dart';
import 'home_stage_rails.dart';

typedef HomeBoardDeferredDeps = ({
  bool Function() mounted,
  bool Function() focusCatalogContinuation,
  bool Function(int, int) focusHomeRailAt,
  bool Function(int, int) focusRow,
});

/// One pending user-directed Down move, retired by age or a changed origin.
class HomeBoardDeferred {
  HomeBoardDeferred(this._deps, this._boardSection, this._stageRailsSection);
  final HomeBoardDeferredDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeStageRails _stageRailsSection;

  // A DPAD-down pressed while everything below was still loading (Trakt row a
  // focusless skeleton, favourites absent, first catalog batch in flight) used
  // to be swallowed with focus frozen in place — the cell handler had already
  // reported the key handled. Instead the press is remembered briefly and
  // completed the moment a row below lands. Origin node is compared by
  // IDENTITY only (never dereferenced — it may be disposed by then): if focus
  // moved elsewhere meanwhile, the deferred move is dropped, so a late load
  // can never yank focus away from the user.
  FocusNode? _pendingDownOrigin;
  int _pendingDownRowIndex = -1; // set when pressed on a catalog row
  String? _pendingDownHomeRowId; // stable id on the globally ordered Home
  int _pendingDownCol = 0;
  DateTime? _pendingDownAt;
  static const Duration pendingDownMaxAge = Duration(seconds: 3);

  void deferDownMove({
    int rowIndex = -1,
    String? homeRowId,
    required int column,
  }) {
    if (!_boardSection.boardCanAdvance && _deps.focusCatalogContinuation()) {
      return;
    }
    _pendingDownOrigin = FocusManager.instance.primaryFocus;
    if (_pendingDownOrigin == null) return;
    _pendingDownRowIndex = rowIndex;
    _pendingDownHomeRowId = homeRowId;
    _pendingDownCol = column;
    _pendingDownAt = DateTime.now();
  }

  void clearDeferredDown() {
    _pendingDownOrigin = null;
    _pendingDownAt = null;
    _pendingDownHomeRowId = null;
  }

  /// Complete a recent deferred DPAD-down, called whenever a row load settles.
  /// Post-frame: the freshly-loaded row's cells only mount on the next build,
  /// and `requestRowFocus` needs mounted cells.
  void maybeCompleteDeferredDown() {
    if (_pendingDownAt == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      final at = _pendingDownAt;
      final origin = _pendingDownOrigin;
      if (at == null || origin == null) return;
      if (DateTime.now().difference(at) > pendingDownMaxAge) {
        clearDeferredDown();
        return;
      }
      if (!identical(FocusManager.instance.primaryFocus, origin)) {
        clearDeferredDown();
        return;
      }
      final col = _pendingDownCol;
      final bool moved;
      final homeRowId = _pendingDownHomeRowId;
      if (homeRowId != null) {
        final rails = _stageRailsSection.canvasRails;
        final current = rails.indexWhere(
          (rail) => _stageRailsSection.canvasRailRowId(rail) == homeRowId,
        );
        moved = current >= 0 && _deps.focusHomeRailAt(current + 1, col);
      } else if (_pendingDownRowIndex >= 0) {
        moved = _deps.focusRow(_pendingDownRowIndex + 1, col);
      } else {
        // From the last favourites row.
        moved = _deps.focusRow(0, col);
      }
      if (moved) clearDeferredDown();
    });
  }
}
