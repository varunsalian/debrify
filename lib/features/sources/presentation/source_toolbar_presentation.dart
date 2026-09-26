import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/addon_search_status.dart';
import '../../../models/torrent_filter_state.dart';
import '../application/source_provider_projection.dart';
import '../application/source_results_controller.dart';
import '../application/source_retry_controller.dart';
import '../application/source_search_controller.dart';
import '../application/source_seasons.dart';
import '../application/source_seasons_controller.dart';
import '../application/source_settings_controller.dart';
import '../models/source_toolbar_state.dart';
import '../models/sources_session.dart';
import 'source_filters_dialog.dart';
import 'source_toolbar.dart';
import 'source_toolbar_controls.dart';

/// View-owned toolbar composition and interaction dispatch. Existing controllers
/// own state; the view keeps subscriptions, row rebuilding and focus resources.
class SourceToolbarPresentation {
  SourceToolbarPresentation({
    required this.context,
    required this.ref,
    required this.session,
    required this.hasSeasonScope,
    required this.isSeries,
    required this.isActive,
    required this.rebuildVisible,
    required this.runSearch,
    required this.retryAddon,
    required this.filterFocus,
    required this.onFilterDown,
  });

  final BuildContext context;
  final WidgetRef ref;
  final SourcesSession session;
  final ValueGetter<bool> hasSeasonScope;
  final ValueGetter<bool> isSeries;
  final ValueGetter<bool> isActive;
  final VoidCallback rebuildVisible;
  final Future<void> Function() runSearch;
  final Future<void> Function(AddonSearchStatus) retryAddon;
  final FocusNode filterFocus;
  final VoidCallback onFilterDown;

  SourceToolbarState get _toolbar =>
      ref.read(sourceResultsProvider(session)).toolbar;

  /// Derived seasons come from the last unscoped result set when metadata
  /// loading fails. Scoped results must not collapse this fallback inventory.
  /// The controller retains that snapshot; the menu reads it at opening time.
  List<int> _seasonMenuNumbers() {
    final seasons = ref.read(sourceSeasonsProvider(session));
    return sourceSeasonMenu(
      available: seasons.available,
      derived: seasons.derived,
      selected: seasons.selected,
    );
  }

  Widget build(ColorScheme scheme, {bool showProviders = true}) {
    final providers = projectSourceProviders(
      torrents: ref.read(sourceResultsProvider(session)).displayed,
      statuses: ref.read(sourceSearchProvider(session)).addonStatuses,
      iptv: ref.read(sourceSearchProvider(session)).iptv,
      priority: ref.read(sourceSettingsProvider(session)).priority.providers,
      aliases: ref.read(sourceSettingsProvider(session)).priority.aliases,
      retrying: ref.read(sourceRetryProvider(session)),
    );

    return buildSourceToolbar(
      context,
      scheme: scheme,
      showProviders: showProviders,
      providersVisible: providers.visible,
      options: providers.options,
      showAll: providers.showAll,
      selectedKey: _toolbar.sourceFilter,
      onSelectProvider: (key) {
        ref.read(sourceResultsProvider(session).notifier).selectProvider(key);
        rebuildVisible();
      },
      onRetryProvider: (key) => unawaited(retryAddon(providers.retries[key]!)),
      messages: () => sourceToolbarMessages(
        statuses: ref.read(sourceSearchProvider(session)).addonStatuses,
        iptv: ref.read(sourceSearchProvider(session)).iptv,
        selectedKey: _toolbar.sourceFilter,
      ),
      controls: SourceToolbarControls(
        showSeason: hasSeasonScope(),
        selectedSeason: ref.read(sourceSeasonsProvider(session)).selected,
        seasonMenuNumbers: _seasonMenuNumbers,
        sortBy: _toolbar.sortBy,
        sortAsc: _toolbar.sortAsc,
        filtersActive: !_toolbar.filters.isEmpty,
        filterFocus: filterFocus,
        onSelectSeason: (next) {
          if (!ref.read(sourceSeasonsProvider(session).notifier).select(next)) {
            return;
          }
          unawaited(runSearch());
        },
        onSelectSort: (value) {
          ref.read(sourceResultsProvider(session).notifier).selectSort(value);
          rebuildVisible();
        },
        onToggleDirection: () {
          ref
              .read(sourceResultsProvider(session).notifier)
              .toggleSortDirection();
          rebuildVisible();
        },
        onOpenFilters: () => unawaited(_openFilters()),
        onFilterDown: onFilterDown,
      ),
      filters: _toolbar.filters,
      onClearFilters: () {
        ref
            .read(sourceResultsProvider(session).notifier)
            .setFilters(const TorrentFilterState.empty());
        rebuildVisible();
      },
    );
  }

  Future<void> _openFilters() async {
    if (!isActive()) return;
    final result = await showSourceFiltersDialog(
      context,
      initialState: _toolbar.filters,
      isSeries: isSeries(),
    );
    if (!isActive() || result == null || result == _toolbar.filters) return;
    ref.read(sourceResultsProvider(session).notifier).setFilters(result);
    rebuildVisible();
  }
}
