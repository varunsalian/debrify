import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/discover/application/discover_card_settings_controller.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_continuation_playback.dart';
import '../../features/home/presentation/home_continuation_return.dart';
import '../../features/home/presentation/home_integration_section.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../models/stremio_addon.dart';
import 'home_board_composition.dart';
import 'home_continuation_content_composition.dart';
import 'home_hero_composition.dart';
import 'home_item_composition.dart';
import 'home_metadata_section.dart';
import 'home_tab_shell_registration.dart';
import 'home_view_bindings.dart';
import 'search_mode_composition.dart';

typedef HomeCatalogPresentationDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeViewBindings Function() view,
  StremioAddon Function() nativeAddon,
  Future<bool> Function() readMergedSeriesEnabled,
  DiscoverCardSettingsController Function() cardSettings,
  int Function() tabIndex,
  Listenable Function() localCompletion,
  Listenable Function() mdblistPlayback,
});

typedef HomeCatalogPresentation = ({
  HomeCatalogBadges badges,
  HomeIntegrationSection integrations,
  HomeMetadataSection metadata,
  HomeRowsNavigation navigation,
  HomeTabShellRegistration tabShell,
});

/// Wires catalog-card metadata, integration state, badges and row navigation.
HomeCatalogPresentation createHomeCatalogPresentation(
  WidgetRef ref,
  HomeCatalogPresentationDeps deps, {
  required HomeBoardWorkflow board,
  required HomeContinuationContent continuation,
  required SearchModeComposition search,
  required SearchInputSection input,
  required TextEditingController searchController,
  required DiscoverSection discover,
  required HomeHeroComposition hero,
  required HomeItemComposition actions,
  required HomeContinuationPlayback playback,
  required HomeContinuationReturn returning,
  required HomeSavedContentSection saved,
}) {
  late final HomeCatalogBadges badges;
  late final HomeIntegrationSection integrations;
  late final HomeMetadataSection metadata;
  late final HomeRowsNavigation navigation;
  badges = HomeCatalogBadges(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      bindings: () => deps.view().homeBoardBindings,
    ),
    board.boardSection,
    continuation.section,
  );
  integrations = HomeIntegrationSection(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      isTelevision: deps.isTelevision,
      bindings: () => deps.view().homeBoardBindings,
    ),
    board.boardSection,
    board.boardConfiguration,
    badges,
    continuation.loading,
    board.controls,
    search.catalog,
    searchController,
  );
  metadata = HomeMetadataSection(
    ref,
    (
      mounted: deps.mounted,
      setState: deps.setState,
      discoverMode: deps.discoverMode,
    ),
    discover,
    search.title,
    continuation.section,
    hero.heroSection,
    hero.heroPreview,
    hero.displaySection,
  );
  navigation = HomeRowsNavigation(
    (
      context: deps.context,
      mounted: deps.mounted,
      setState: deps.setState,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      nativeAddon: deps.nativeAddon,
      readMergedSeriesEnabled: deps.readMergedSeriesEnabled,
      readCardSettings: ({required isCurrent}) =>
          deps.cardSettings().readSnapshot(isCurrent: isCurrent),
    ),
    board.boardSection,
    hero.displaySection,
    badges,
    actions.items,
    actions.catalog,
    integrations,
    continuation.section,
    playback,
    returning,
  );
  final tabShell = HomeTabShellRegistration(
    (
      mounted: deps.mounted,
      tabIndex: deps.tabIndex,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      localCompletion: deps.localCompletion,
      mdblistPlayback: deps.mdblistPlayback,
    ),
    input.focusContent,
    continuation.loading,
    saved,
    search.mode,
    search.title,
    navigation,
  );
  return (
    badges: badges,
    integrations: integrations,
    metadata: metadata,
    navigation: navigation,
    tabShell: tabShell,
  );
}
