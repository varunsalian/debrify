import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../home/models/home_catalog_search_status.dart';
import '../models/search_session.dart';
import '../models/catalog_search_state.dart';
import '../application/catalog_search_controller.dart';
import 'search_result_bindings.dart';
import 'catalog_search_projection.dart';
import 'catalog_search_prompt.dart';
import 'catalog_sources_dialog.dart';

typedef CatalogSearchSectionDeps = ({
  SearchSession Function() session,
  SearchResultBindings Function() bindings,
  bool Function() mounted,
  bool Function() isTelevision,
  FocusNode Function() searchField,
  void Function(List<CatalogSection>) applySections,
  FocusNode? Function() firstResult,
  void Function(FocusNode) completeSubmitFocus,
  VoidCallback cancelSubmitFocus,
  bool Function() catalogModeActive,
  VoidCallback focusSearch,
  VoidCallback focusSidebar,
  BuildContext Function() context,
});

/// Catalog submit and Sources actions preserve batch publication and focus handoff.
class CatalogSearchSection implements HomeCatalogSearchStatus {
  CatalogSearchSection(this._ref, this._deps);
  final WidgetRef _ref;
  final CatalogSearchSectionDeps _deps;

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  // Catalogs that errored (timeout / HTTP / network) during the current
  // catalog search — distinct from "returned no results". Drives the quiet
  // "N sources didn't respond" note so failing addons don't just vanish.

  CatalogSearchState get catalogState => _deps.bindings().catalog;
  CatalogSearchController get catalogController =>
      _ref.read(catalogSearchProvider(_deps.session()).notifier);
  @override
  String get catalogQuery => catalogState.query;
  @override
  int get catalogFailures => catalogState.failures;
  @override
  void clearCatalogResults() => catalogController.clear();

  /// DPAD focus for the catalog-mode "Sources" button (empty-prompt state) —
  /// its keyword-mode twin, for picking which searchable addons are queried.
  final FocusNode catalogSourcesBtnFocus = FocusNode(
    debugLabel: 'catalog_sources_btn',
  );

  /// Cross-addon catalog search, grouped as one horizontal row per addon so it
  /// matches the board (not a merged grid).
  @override
  Future<void> runCatalogSearch(String query) async {
    // Reclaim TV focus before disposing the previous result nodes.
    if (_deps.isTelevision() && !_deps.searchField().hasFocus) {
      _deps.searchField().requestFocus();
    }
    final completion = catalogController.search(
      query,
      batchResults: _deps.isTelevision(),
    );
    _deps.applySections(const []);
    final result = await completion;
    if (!_deps.mounted() || result == CatalogSearchCompletion.stale) return;
    if (result == CatalogSearchCompletion.failed) {
      _deps.cancelSubmitFocus();
      return;
    }
    if (_deps.isTelevision()) {
      // One stable batch, including empty results. Phone/desktop rows arrive
      // through the subscription without replacing already focused rows.
      _deps.applySections(catalogState.rows.map(catalogSearchSection).toList());
      if (_deps.firstResult() != null) {
        _deps.completeSubmitFocus(_deps.firstResult()!);
      } else {
        _deps.cancelSubmitFocus();
      }
    }
  }

  /// Catalog-mode twin of [_keywordSection.kwSourcesButtonVisible]: the Sources button shown
  /// on the empty catalog prompt (Search tab, no query yet, not mid-search).
  bool get catalogSourcesButtonVisible =>
      _deps.catalogModeActive() && catalogQuery.isEmpty && !catalogSearching;

  Widget buildSearchPrompt(BuildContext context) => buildCatalogSearchPrompt(
    context,
    sourcesButton: () => catalogSourcesButton(context),
  );

  Widget catalogSourcesButton(BuildContext context) => buildSearchSourcesButton(
    context,
    focusNode: catalogSourcesBtnFocus,
    onOpen: openCatalogSources,
    onUp: _deps.focusSearch,
    onSidebar: _deps.focusSidebar,
  );

  /// Open the catalog Sources dialog, then re-run the search if one is active
  /// (so toggling an addon reflects immediately, like the keyword twin).
  Future<void> openCatalogSources() async {
    final context = _deps.context();
    await showDialog<void>(
      context: context,
      builder: (_) => CatalogSourcesDialog(session: _deps.session()),
    );
    if (!context.mounted) return;
    if (catalogQuery.isNotEmpty) {
      runCatalogSearch(catalogQuery);
    }
  }

  @override
  bool get catalogSearching => catalogState.searching;
}
