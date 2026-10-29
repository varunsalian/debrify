import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_body.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_filter_bar.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_filters.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_install_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_layout.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_management.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_menus.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_sections.dart';
import 'package:debrify/services/addon_auto_update.dart';
import 'package:flutter/material.dart';

typedef AddonHubCompositionDeps = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

typedef AddonHubOwners = ({
  AddonHubInstalledState installedState,
  AddonHubMarketState marketState,
  AddonHubNavigationState navigationState,
  AddonHubEngineState engineState,
});

AddonHubSections createAddonHubSections(
  AddonHubCompositionDeps deps,
  AddonHubOwners owners,
) {
  final sections = AddonHubSections();
  sections.loadingSlot = AddonHubLoading((
    mounted: deps.mounted,
    setState: deps.setState,
    installedState: owners.installedState,
    marketState: owners.marketState,
  ));
  sections.engineLoadingSlot = AddonHubEngineLoading((
    engineState: owners.engineState,
    mounted: deps.mounted,
    setState: deps.setState,
  ));
  sections.engineActionsSlot = AddonHubEngineActions((
    context: deps.context,
    engineState: owners.engineState,
    loadEngines: sections.engineLoading.loadEngines,
    mounted: deps.mounted,
  ));
  sections.navigationSlot = AddonHubNavigation((
    navigationState: owners.navigationState,
    setState: deps.setState,
    mounted: deps.mounted,
    engineState: owners.engineState,
    loadEngines: sections.engineLoading.loadEngines,
    marketState: owners.marketState,
    loadMarket: sections.loading.loadMarket,
  ));
  sections.filtersSlot = AddonHubFilters((
    installedState: owners.installedState,
    navigationState: owners.navigationState,
  ));
  sections.installActionsSlot = AddonHubInstallActions((
    context: deps.context,
    installedState: owners.installedState,
    mounted: deps.mounted,
    loadInstalled: sections.loading.loadInstalled,
    navigationState: owners.navigationState,
  ));
  sections.managementSlot = AddonHubManagement((
    context: deps.context,
    installedState: owners.installedState,
    mounted: deps.mounted,
  ));
  sections.menusSlot = AddonHubMenus((
    context: deps.context,
    toggleAddon: sections.management.toggleAddon,
    updateAddon: sections.management.updateAddon,
    renameAddon: sections.management.renameAddon,
    removeAddon: sections.management.removeAddon,
    navigationState: owners.navigationState,
    importJson: sections.installActions.importJson,
    updateAll: sections.management.updateAll,
    deleteAll: sections.management.deleteAll,
    autoUpdateEnabled: AddonAutoUpdate.isEnabled,
    setAutoUpdate: AddonAutoUpdate.setEnabled,
  ));
  sections.filterBarSlot = AddonHubFilterBar((
    navigationState: owners.navigationState,
    selectKind: sections.navigation.selectKind,
    selectSource: sections.navigation.selectSource,
    setState: deps.setState,
    toggleSearch: sections.navigation.toggleSearch,
    addByUrl: sections.installActions.addByUrl,
    showActionsMenu: sections.menus.showActionsMenu,
    importEngineFromFile: sections.engineActions.importEngineFromFile,
    loadEngines: sections.engineLoading.loadEngines,
    focusFirstRow: sections.navigation.focusFirstRow,
    context: deps.context,
  ));
  sections.installedListSlot = AddonHubInstalledList((
    installedState: owners.installedState,
    matchesFilters: sections.filters.matchesFilters,
    emptyState:
        ({
          required IconData icon,
          required String title,
          required String subtitle,
          Widget? action,
        }) => sections.body.emptyState(
          icon: icon,
          title: title,
          subtitle: subtitle,
          action: action,
        ),
    navigationState: owners.navigationState,
    showOptions: sections.menus.showOptions,
    context: deps.context,
    setState: deps.setState,
    mounted: deps.mounted,
  ));
  sections.marketListSlot = AddonHubMarketList((
    navigationState: owners.navigationState,
    marketState: owners.marketState,
    emptyState:
        ({
          required IconData icon,
          required String title,
          required String subtitle,
          Widget? action,
        }) => sections.body.emptyState(
          icon: icon,
          title: title,
          subtitle: subtitle,
          action: action,
        ),
    loadMarket: sections.loading.loadMarket,
    matchesFilters: sections.filters.matchesFilters,
    isInstalled: sections.filters.isInstalled,
    installedState: owners.installedState,
    installFromMarket: sections.installActions.installFromMarket,
    configureInBrowser: sections.installActions.configureInBrowser,
  ));
  sections.engineListSlot = AddonHubEngineList((
    engineState: owners.engineState,
    emptyState:
        ({
          required IconData icon,
          required String title,
          required String subtitle,
          Widget? action,
        }) => sections.body.emptyState(
          icon: icon,
          title: title,
          subtitle: subtitle,
          action: action,
        ),
    loadEngines: sections.engineLoading.loadEngines,
    navigationState: owners.navigationState,
    deleteEngine: sections.engineActions.deleteEngine,
    installEngine: sections.engineActions.installEngine,
  ));
  sections.bodySlot = AddonHubBody((
    navigationState: owners.navigationState,
    buildEngineList: sections.engineList.buildEngineList,
    buildInstalledList: sections.installedList.buildInstalledList,
    buildMarketList: sections.marketList.buildMarketList,
  ));
  sections.layoutSlot = AddonHubLayout((
    onPageKey: sections.navigation.onPageKey,
    buildHeader: sections.body.buildHeader,
    buildFilterBar: sections.filterBar.buildFilterBar,
    buildBody: sections.body.buildBody,
  ));
  return sections;
}
