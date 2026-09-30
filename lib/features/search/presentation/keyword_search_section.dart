import '../../../models/source_appearance.dart';
import '../application/keyword_appearance_controller.dart';
import 'keyword_results_projection.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/torrent.dart';
import '../../../models/torrent_filter_state.dart';
import '../../../widgets/cinema_sources_layout.dart';
import '../application/keyword_search_controller.dart';
import '../application/keyword_results_controller.dart';
import '../application/keyword_cache_controller.dart';
import '../models/keyword_search_state.dart';
import '../models/keyword_results_state.dart';
import '../models/search_session.dart';
import 'search_result_bindings.dart';
import 'keyword_focus_controller.dart';
import 'keyword_viewport.dart';
import '../models/search_mode.dart';

typedef KeywordSearchSectionDeps = ({
  SearchSession Function() session,
  SearchResultBindings Function() bindings,
  SearchMode Function() mode,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  VoidCallback focusSearch,
  VoidCallback focusSearchNode,
  VoidCallback focusSidebar,
  void Function(FocusNode) completeSubmitFocus,
  VoidCallback cancelSubmitFocus,
});

/// Owns route-local Keyword streaming adoption, selection and focus ordering.
class KeywordSearchSection {
  KeywordSearchSection(this._ref, this._deps);
  final WidgetRef _ref;
  final KeywordSearchSectionDeps _deps;
  late final projection = KeywordResultsProjection(() => keywordResults);
  int get kwPendingNewCount => projection.kwPendingNewCount;
  List<Torrent> get kwFullSet => projection.kwFullSet;
  List<String> get kwSourceList => projection.kwSourceList;
  bool get kwTabsVisible => projection.kwTabsVisible;
  List<Torrent> get kwSelectableResults => projection.kwSelectableResults;
  bool get kwHasProviderFilter => projection.kwHasProviderFilter;
  int get kwProviderFilterActive => projection.kwProviderFilterActive;
  // Keyword torrent-search state (submit-based).
  KeywordSearchController get keywordSearchController =>
      _ref.read(keywordSearchProvider(_deps.session()).notifier);
  KeywordSearchState get keywordSearchState => _deps.bindings().search;
  bool get kwLoading => keywordSearchState.loading;
  String? get kwError => keywordSearchState.error;
  String get kwQuery => keywordSearchState.query;
  KeywordResultsController get keywordResultsController =>
      _ref.read(keywordResultsProvider(_deps.session()).notifier);
  KeywordResultsState get keywordResults => _deps.bindings().results;
  List<Torrent> get kwAll => keywordResults.all;
  List<Torrent> get kwResults => keywordResults.results;
  late final keywordFocus = KeywordFocusController(
    focusSearch: _deps.focusSearch,
    focusSidebar: _deps.focusSidebar,
    focusAboveToolbar: focusAboveKeywordToolbar,
    hasAccessibleArrivals: () => kwPendingNewCount > 0 && !kwSelectionMode,
  );
  List<FocusNode> get kwNodes => keywordFocus.rows;
  final kwCinemaKey = GlobalKey<CinemaSourcesLayoutState>();
  // Keyboard/DPAD focus targets for the keyword toolbar pills (Sort / Filters /
  // Providers / Sources / Select). A fixed pool of 5 covers the most pills ever
  // shown.
  List<FocusNode> get kwToolbarNodes => keywordFocus.toolbar;
  TorrentFilterState get kwFilters => keywordResults.filters;
  String get kwSort => keywordResults.sort;
  // Sort direction for kwSort (ignored for 'relevance', which is engine order).
  // Defaults follow each field's natural direction; the sort dialog can flip it.
  bool get kwSortAsc => keywordResults.sortAscending;
  KeywordCacheController get keywordCacheController =>
      _ref.read(keywordCacheProvider(_deps.session()).notifier);
  Map<String, List<String>> get kwCache => _deps.bindings().cache.badges;

  // Provider (stream-type) multi-select filter, ported from the old search
  // screen: results are grouped into "Direct" (direct/external URL streams) and
  // "Torrent" providers by their [Torrent.source], each independently filterable
  // by which sources are ticked. Empty count maps mean "no such group".
  Map<String, int> get kwDirectCounts => keywordResults.providers.directCounts;
  Map<String, int> get kwTorrentCounts =>
      keywordResults.providers.torrentCounts;
  Set<String> get kwSelectedDirect => keywordResults.providers.selectedDirect;
  Set<String> get kwSelectedTorrent => keywordResults.providers.selectedTorrent;

  /// True when the results list is being narrowed to TorBox-cached torrents
  /// only (TorBox is the sole usable debrid provider and its cache-check is on)
  /// — mirrors the old screen's `_showingTorboxCachedOnly`. Drives the banner.
  bool get kwCachedOnly => _deps.bindings().cache.cachedOnly;

  // Bulk-selection state for keyword results (mirrors Home's multi-select).
  bool get kwSelectionMode => keywordResults.selectionMode;
  Set<String> get kwSelected => keywordResults.selected;

  int get kwSearchToken => keywordSearchState.request;
  bool get kwSearching => keywordSearchState.searching;

  /// Set on the first real user interaction (scroll drag, row DPAD nav, row
  /// tap/long-press, toolbar use) — later arrivals then park in [kwPending]
  /// behind the "+N new results" pill instead of reshuffling the list.
  bool get kwStreamFrozen => keywordResults.frozen;

  /// Full (unfiltered) result set parked while frozen; adopted by the pill,
  /// any toolbar action, or a source-tab tap.
  List<Torrent>? get kwPending => keywordResults.pending;

  /// DPAD focus for the "+N new results" pill.
  FocusNode get kwPillFocus => keywordFocus.arrivals;

  /// DPAD focus for the pre-search "Sources" button (shown in the empty
  /// keyword state before a query). Without its own node it's a bare InkWell
  /// unreachable by the remote — you couldn't pick sources before searching.
  FocusNode get kwSourcesBtnFocus => keywordFocus.sources;

  /// Source tab strip (All / per-source), single-select on top of the
  /// Providers multi-select. Null = All.
  String? get kwSourceTab => keywordResults.sourceTab;
  List<FocusNode> get kwTabNodes => keywordFocus.tabs;

  final keywordViewport = KeywordViewport();
  ScrollController get kwScroll => keywordViewport.scroll;

  Future<void> loadDefaultKeywordFilters() async {
    final changed = await keywordResultsController.loadDefaults();
    if (_deps.mounted() && changed && kwAll.isNotEmpty) syncKeywordResults();
  }

  /// One-shot: restore DPAD focus to the toolbar at the FIRST streamed paint
  /// (set by _openKeywordSources, whose re-search unmounts the focused pill).
  /// Consumed/cleared on present so a completion refocus can never yank the
  /// remote off a row the user reached mid-stream.
  bool kwRefocusToolbar = false;

  Future<void> runKeyword(String query, {bool refocusToolbar = false}) async {
    // Reject outgoing-view actions before changing its UI or resolving services.
    if (query.isEmpty || !keywordSearchController.isCurrent) return;
    keywordResultsController.begin();
    kwRefocusToolbar = refocusToolbar;
    await keywordSearchController.search(query);
  }

  /// Applies a (provisional or final) raw result set: recompute providers and
  /// the filtered view, or — once the user has interacted ([kwStreamFrozen])
  /// — park it behind the "+N new results" pill so rows never reshuffle
  /// mid-read.
  void presentKwStreaming(List<Torrent> raw, int token) {
    if (!_deps.mounted() || token != kwSearchToken) return;
    // The strip live-updates on every present (frozen or not), so if the
    // remote is ON a tab, capture its source before indices shift.
    final tabAnchor = focusedKwTabSource();
    if (kwStreamFrozen) {
      // The user has taken over focus — drop the pending toolbar refocus.
      kwRefocusToolbar = false;
      keywordResultsController.present(raw);
      syncKwTabNodes(); // live tabs: nodes track the parked set's sources
      _deps.setState(() {}); // pill count + tab strip update
      reanchorKwTab(tabAnchor);
      return;
    }
    keywordResultsController.present(raw);
    syncKeywordResults();
    reanchorKwTab(tabAnchor);
    if (kwToolbarVisible) {
      _deps.completeSubmitFocus(kwToolbarNodes.first);
    }
    if (kwRefocusToolbar) {
      // The Sources-dialog re-search unmounted the focused toolbar; the
      // toolbar just remounted with this first paint — put the remote back
      // NOW, not at completion (rows are interactive from the first batch).
      kwRefocusToolbar = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_deps.mounted() && kwToolbarVisible) {
          kwToolbarNodes.first.requestFocus();
        }
      });
    }
  }

  /// Completion-only steps: validate the source tab against the final set,
  /// hide the searching strip, and run the cache-badge check.
  void finishKeyword(int token) {
    if (!_deps.mounted() || token != kwSearchToken) return;
    // Validate against the authoritative FULL set (pending included) — an
    // early batch that merely hasn't delivered a source yet must not clear
    // the user's tab mid-stream, so this check only runs here.
    final full = kwPending ?? kwAll;
    if (keywordResultsController.finish()) syncKeywordResults();
    _deps.setState(() {}); // searching strip off
    // Completion: await in-flight batch checks, sweep stragglers, then settle
    // cached-only mode over the authoritative full set.
    unawaited(finalizeKeywordCache(full, token));
  }

  /// First real user interaction → stop live-reshuffling; buffer new arrivals
  /// behind the pill instead.
  void kwFreeze() {
    keywordResultsController.freeze();
    _deps.cancelSubmitFocus();
  }

  /// Freeze AND fold any parked arrivals in — used by toolbar/dialog/tab
  /// actions, so the user always sorts/filters/selects over the complete set.
  void kwFreezeAndAdopt() {
    kwFreeze();
    kwAdoptPending();
  }

  /// Folds the parked result set into the list (pill tap / toolbar use) and
  /// refreshes cache badges for the fresh rows.
  void kwAdoptPending() {
    final p = kwPending;
    if (p == null) return;
    // Identity-preserving refocus (Sources-list parity): folding arrivals in
    // can insert rows above the DPAD focus — keep the remote on the SAME
    // torrent, not the same index. This also keeps a long-pressed row under
    // its checkmark when enterKwSelection adopts before toggling.
    Torrent? focusedTorrent;
    for (var i = 0; i < kwNodes.length && i < kwResults.length; i++) {
      if (kwNodes[i].hasFocus) {
        focusedTorrent = kwResults[i];
        break;
      }
    }
    if (!keywordResultsController.adopt()) return;
    syncKeywordResults();
    if (focusedTorrent != null) {
      final key = KeywordResultsProjection.kwRowKey(focusedTorrent);
      final idx = kwResults.indexWhere(
        (t) => KeywordResultsProjection.kwRowKey(t) == key,
      );
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_deps.mounted() && idx < kwNodes.length) {
            kwNodes[idx].requestFocus();
          }
        });
      }
    }
    unawaited(keywordCacheController.check(kwAll, kwSearchToken));
  }

  /// Which SOURCE the focused tab points at ('' = the All tab, null = the
  /// strip isn't focused). Captured BEFORE a strip rebuild so focus can be
  /// re-anchored by identity — new sources insert alphabetically and shift
  /// positional node indices under the remote.
  String? focusedKwTabSource() {
    for (var i = 0; i < kwTabNodes.length; i++) {
      if (kwTabNodes[i].hasFocus) {
        if (i == 0) return '';
        final sources = kwSourceList;
        return i - 1 < sources.length ? sources[i - 1] : '';
      }
    }
    return null;
  }

  /// Post-frame counterpart of [focusedKwTabSource]: refocus the tab that
  /// carries [source] at its NEW index (All when it vanished).
  void reanchorKwTab(String? source) {
    if (source == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      final idx = source.isEmpty ? 0 : kwSourceList.indexOf(source) + 1;
      keywordFocus.focusTab(idx > 0 && idx < kwTabNodes.length ? idx : 0);
    });
  }

  /// Completion-only cache changes explicitly recompute the displayed rows.
  void recomputeKeyword() {
    keywordResultsController.recompute();
    syncKeywordResults();
  }

  void syncKeywordResults() {
    syncKwNodes(kwResults.length);
    syncKwTabNodes();
    _deps.setState(() {});
  }

  void syncKwNodes(int length) => keywordFocus.syncRows(length);
  void syncKwTabNodes() => keywordFocus.syncTabs(kwSourceList.length);

  /// Badge updates never reconcile row nodes. Cached-only mode changes do,
  /// and only the completion accepted by this still-mounted search may do so.
  Future<void> finalizeKeywordCache(List<Torrent> full, int token) async {
    final changed = await keywordCacheController.finish(full, token);
    if (!_deps.mounted() || token != kwSearchToken) return;
    if (changed) recomputeKeyword();
  }

  /// Whether the keyword results toolbar (Sort/Filters/Sources/…) is on-screen,
  /// so focus can route into it between the search field and the result rows.
  bool get kwToolbarVisible =>
      _deps.mode() == SearchMode.keyword &&
      !kwLoading &&
      kwError == null &&
      kwQuery.isNotEmpty;

  /// Whether the pre-search "Sources" button is on-screen — the empty keyword
  /// state, before a query. It's the only focusable content then, so DPAD-down
  /// from the search field must land on it (see the field's key handler).
  bool get kwSourcesButtonVisible =>
      _deps.mode() == SearchMode.keyword &&
      !kwLoading &&
      kwError == null &&
      kwQuery.isEmpty;

  void focusAboveKeywordResults() {
    if (kwPendingNewCount > 0 && !kwSelectionMode) {
      kwPillFocus.requestFocus();
    } else if (kwToolbarVisible) {
      kwToolbarNodes.first.requestFocus();
    } else {
      _deps.focusSearchNode();
    }
  }

  void setKwSourceTab(String? source) {
    final tabHadFocus = kwTabNodes.any((n) => n.hasFocus);
    // A deliberate reshuffle: fold parked arrivals in so the tab filters the
    // complete set (also freezes further live updates).
    kwFreezeAndAdopt();
    if (keywordResultsController.setSourceTab(source)) syncKeywordResults();
    source = kwSourceTab;
    // Tab nodes are positional and the adopt can re-sort kwSourceList —
    // re-anchor DPAD focus onto the tab that was actually chosen.
    if (tabHadFocus) {
      final s = source;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        final idx = s == null ? 0 : kwSourceList.indexOf(s) + 1;
        keywordFocus.focusTab(idx > 0 && idx < kwTabNodes.length ? idx : 0);
      });
    }
  }

  /// Resolve the route's current target above the Keyword toolbar.
  void focusAboveKeywordToolbar() {
    // Source tabs sit between the toolbar and the search field — land on
    // the active tab so the strip context is obvious. Hidden during
    // multi-select (the strip is suppressed then — see _buildKeyword).
    if (!kwSelectionMode && kwCinemaKey.currentState != null) {
      kwCinemaKey.currentState!.focusSelectedProvider();
      return;
    }
    if (!kwSelectionMode && kwTabsVisible && kwTabNodes.isNotEmpty) {
      final tabs = kwSourceList;
      final active = kwSourceTab == null ? 0 : tabs.indexOf(kwSourceTab!) + 1;
      keywordFocus.focusTab(
        active >= 0 && active < kwTabNodes.length ? active : 0,
      );
      return;
    }
    _deps.focusSearch();
  }

  void disposeKwNodes() => keywordFocus.clearRows();
  late final KeywordAppearanceController _keywordAppearanceController;
  late final ProviderSubscription<SourceAppearance>
  _keywordAppearanceSubscription;

  Future<void> loadSourceTextFormatting({bool Function()? isCurrent}) =>
      _keywordAppearanceController.load(
        isCurrent: () => _deps.mounted() && (isCurrent?.call() ?? true),
        onAccepted: () => _deps.setState(() {}),
      );

  void startAppearance() {
    _keywordAppearanceSubscription = _ref.listenManual(
      keywordAppearanceProvider(_deps.session()),
      (previous, next) {},
    );
    _keywordAppearanceController = _ref.read(
      keywordAppearanceProvider(_deps.session()).notifier,
    );
  }

  SourceAppearance get appearance => _keywordAppearanceSubscription.read();
  void closeAppearance() => _keywordAppearanceSubscription.close();
  void clearKeywordSearch() {
    keywordSearchController.clear();
    disposeKwNodes();
    keywordResultsController.clear();
  }
}
