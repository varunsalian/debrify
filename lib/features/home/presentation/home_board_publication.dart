import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../search/presentation/catalog_search_section.dart';
import 'home_board_section.dart';
import 'home_stage_section.dart';

typedef HomeBoardPublicationDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  Object? Function() scope,
  bool Function() boardHasFocus,
  VoidCallback settleAutoFocus,
  void Function(List<CatalogSection>, {bool preserveFocus, bool incremental})
  applySections,
  VoidCallback autoFocus,
  VoidCallback completeDeferredDown,
  void Function({bool resumeDeferred}) autoFill,
});

/// Publishes accepted Home rows only when their route is visible and scope current.
class HomeBoardPublication {
  HomeBoardPublication(
    this._deps,
    this._boardSection,
    this._catalogSection,
    this._stageSection,
    this._ready,
  );
  final HomeBoardPublicationDeps _deps;
  final HomeBoardSection _boardSection;
  final CatalogSearchSection _catalogSection;
  final HomeStageSection _stageSection;
  final ValueNotifier<bool> _ready;

  void publishHomeProgress(
    List<CatalogSection> rows,
    bool first,
    int generation,
    Object? scope,
  ) {
    if (!_deps.mounted() ||
        generation != _boardSection.boardLoadGen ||
        scope != _deps.scope()) {
      return;
    }
    _boardSection.homeCatalogController.replaceRows(rows);
    if (_catalogSection.catalogQuery.isNotEmpty ||
        _catalogSection.catalogSearching) {
      return;
    }
    if (!(ModalRoute.of(_deps.context())?.isCurrent ?? true)) {
      // Keep data, not new image widgets, while a detail page/player covers
      // Home. Returning first restores the old focused row, then inserts the
      // arrivals with the same scroll-anchor protection as foreground loads.
      _boardSection.homePublication.defer((
        rows: rows,
        first: first,
        generation: generation,
        scope: scope,
      ));
      return;
    }
    _boardSection.homePublication.clear();
    if (!first && _deps.boardHasFocus()) _deps.settleAutoFocus();
    _deps.setState(() => _boardSection.publishRows(hasRows: rows.isNotEmpty));
    _deps.applySections(rows, preserveFocus: !first, incremental: !first);
    _ready.value = true;
    _deps.autoFocus();
    _deps.completeDeferredDown();
    _stageSection.maybeCompleteStageAdvance();
  }

  void resumeHomeProgress() => _boardSection.homePublication.resume(
    isVisible: () =>
        _deps.mounted() && (ModalRoute.of(_deps.context())?.isCurrent ?? true),
    isCurrent: (pending) =>
        pending.generation == _boardSection.boardLoadGen &&
        pending.scope == _deps.scope(),
    publish: (pending) => publishHomeProgress(
      pending.rows,
      pending.first,
      pending.generation,
      pending.scope,
    ),
    onResumed: () => _deps.autoFill(resumeDeferred: true),
  );
}
