import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_filter_bar.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_filters.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_install_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_management.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_menus.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation.dart';

class AddonHubSections {
  AddonHubLoading? loadingSlot;
  AddonHubLoading get loading => loadingSlot!;
  AddonHubEngineLoading? engineLoadingSlot;
  AddonHubEngineLoading get engineLoading => engineLoadingSlot!;
  AddonHubEngineActions? engineActionsSlot;
  AddonHubEngineActions get engineActions => engineActionsSlot!;
  AddonHubNavigation? navigationSlot;
  AddonHubNavigation get navigation => navigationSlot!;
  AddonHubFilters? filtersSlot;
  AddonHubFilters get filters => filtersSlot!;
  AddonHubInstallActions? installActionsSlot;
  AddonHubInstallActions get installActions => installActionsSlot!;
  AddonHubManagement? managementSlot;
  AddonHubManagement get management => managementSlot!;
  AddonHubMenus? menusSlot;
  AddonHubMenus get menus => menusSlot!;
  AddonHubFilterBar? filterBarSlot;
  AddonHubFilterBar get filterBar => filterBarSlot!;
  AddonHubInstalledList? installedListSlot;
  AddonHubInstalledList get installedList => installedListSlot!;
  AddonHubMarketList? marketListSlot;
  AddonHubMarketList get marketList => marketListSlot!;
  AddonHubEngineList? engineListSlot;
  AddonHubEngineList get engineList => engineListSlot!;
}
