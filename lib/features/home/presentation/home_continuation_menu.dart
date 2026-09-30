import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_cw_hold_preference.dart';
import '../models/home_catalog_session.dart';
import 'home_continue_watching_actions.dart';
import 'home_continuation_projection.dart';
import 'home_playback_navigation.dart';
import 'home_stage_rows.dart';

typedef HomeContinuationMenuDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() pikpakOnly,
  HomeCatalogSession Function() session,
  void Function(List<FocusNode>, int) requestRowFocus,
  VoidCallback leaveBoardTop,
});

/// Continuation hold/menu dispatch and focus restoration after a removal.
class HomeContinuationMenu {
  HomeContinuationMenu(this._ref, this._deps, this._projection, this._playback);
  final WidgetRef _ref;
  final HomeContinuationMenuDeps _deps;
  final HomeContinuationProjection _projection;
  final HomePlaybackNavigation _playback;

  /// Focus a card in the Continue Watching row at [cwIndex] (index into the
  /// visible CW rows), clamping the column to that row's length. Returns
  /// whether a focus move was actually attempted — false means the target row
  /// doesn't exist (yet), so callers can fall through or defer instead of
  /// silently swallowing the DPAD press.
  bool focusCwRow(int cwIndex, int column) {
    final rows = _projection.cwRows;
    if (cwIndex < 0 || cwIndex >= rows.length) return false;
    final nodes = rows[cwIndex].nodes;
    if (nodes.isEmpty) return false;
    _deps.requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  // ── Continue Watching card menu (long-press / hold-OK) ────────────────────

  final continueWatchingActions = HomeContinueWatchingActions();

  Future<void> openCwCardMenu(
    HomeContinuationRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) async {
    if (!_playback.catalogNavigationCurrent()) return;
    final readPreference = _ref.read(
      homeCwHoldPreferenceProvider(_deps.session().owner),
    );
    await continueWatchingActions.open(
      context: _deps.context(),
      row: row,
      item: item,
      pikpakOnly: _deps.pikpakOnly(),
      isTelevision: () => _deps.isTelevision(),
      isCurrent: _playback.catalogNavigationCurrent,
      readHoldToQuickPlay: readPreference,
      refocusAfterRemoval: () => refocusAfterCwRemoval(cwIndex, col),
    );
  }

  /// Put TV focus back on the board after a removal: the card that had it is
  /// gone (and its FocusNode with it, if the row shrank), which would otherwise
  /// leave the remote dead until the global reclaim listener notices.
  void refocusAfterCwRemoval(int cwIndex, int col) {
    if (!_deps.isTelevision()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_playback.catalogNavigationCurrent()) return;
      // Same index first: if this row survived it's still here, and if it
      // emptied out the row below has slid into its place.
      if (focusCwRow(cwIndex, col)) return;
      for (var i = cwIndex - 1; i >= 0; i--) {
        if (focusCwRow(i, col)) return;
      }
      // No Continue Watching rows left at all — hand the remote to the shell.
      _deps.leaveBoardTop();
    });
  }
}
