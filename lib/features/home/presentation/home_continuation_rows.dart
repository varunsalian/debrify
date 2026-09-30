import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import 'home_continuation_row.dart';
import 'home_trakt_skeleton_row.dart';
import 'home_stage_rows.dart';
import 'home_continuation_section.dart';
import 'home_continuation_menu.dart';

typedef HomeContinuationRowsDeps = ({
  Widget Function({required String title, String? tag, VoidCallback? onSeeAll})
  header,
  bool Function() isTelevision,
  double Function() posterWidth,
  double Function() cellHeight,
  double Function() aspectRatio,
  bool Function() showTitleOverlay,
  String? Function(StremioMeta) artOf,
  bool Function(StremioMeta) isBound,
  VoidCallback sidebar,
  void Function(StremioMeta) onFocused,
  void Function(String, int, int) focusRelativeRail,
});

/// Continuation and loading-row renderer arguments, with the existing widget tree.
class HomeContinuationRows {
  HomeContinuationRows(this._deps, this._section, this._menu);
  final HomeContinuationRowsDeps _deps;
  final HomeContinuationSection _section;
  final HomeContinuationMenu _menu;

  Widget buildContinueWatchingRow(
    HomeContinuationRow row,
    int cwIndex,
    String homeRowId,
  ) => buildHomeContinuationRow(
    row: row,
    header: _deps.header(
      title: row.title,
      tag: row.tag,
      onSeeAll: row.onSeeAll,
    ),
    isTelevision: _deps.isTelevision(),
    posterWidth: _deps.posterWidth(),
    cellHeight: _deps.cellHeight(),
    aspectRatio: () => _deps.aspectRatio(),
    showTitleOverlay: () => _deps.showTitleOverlay(),
    artOf: _deps.artOf,
    isBound: _deps.isBound,
    onLeftEdge: _deps.sidebar,
    onFocused: _deps.onFocused,
    onMenu: (item, col) => _menu.openCwCardMenu(row, item, cwIndex, col),
    onUp: (col) => _deps.focusRelativeRail(homeRowId, -1, col),
    onDown: (col) => _deps.focusRelativeRail(homeRowId, 1, col),
  );

  /// A skeleton Trakt Continue Watching row shown while the account's fetch is
  /// still in flight (see [_continuationProjection.traktReserving]). Sized identically to a real CW row
  /// — same header, poster width and cell height — so when the data arrives and
  /// replaces it there's zero layout shift. Purely decorative: no focus nodes,
  /// so the DPAD skips over it entirely. [idx] is 0 (Movies) or 1 (Shows).
  Widget buildTraktSkeletonRow(int idx) {
    final posterW = _deps.posterWidth();
    final cellH = _deps.cellHeight();
    final rowH = cellH + 14;
    return HomeTraktSkeletonRow(
      header: _deps.header(
        title: 'Trakt Continue Watching',
        tag: idx == 0 ? (_section.cwMergeTrakt ? null : 'Movies') : 'Shows',
      ),
      posterW: posterW,
      cellH: cellH,
      rowH: rowH,
    );
  }
}
