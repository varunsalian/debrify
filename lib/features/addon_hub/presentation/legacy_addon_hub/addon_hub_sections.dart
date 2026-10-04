import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_install_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_management.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_menus.dart';

class AddonHubSections {
  AddonHubLoading? loadingSlot;
  AddonHubLoading get loading => loadingSlot!;
  AddonHubEngineLoading? engineLoadingSlot;
  AddonHubEngineLoading get engineLoading => engineLoadingSlot!;
  AddonHubEngineActions? engineActionsSlot;
  AddonHubEngineActions get engineActions => engineActionsSlot!;
  AddonHubInstallActions? installActionsSlot;
  AddonHubInstallActions get installActions => installActionsSlot!;
  AddonHubManagement? managementSlot;
  AddonHubManagement get management => managementSlot!;
  AddonHubMenus? menusSlot;
  AddonHubMenus get menus => menusSlot!;
  AddonHubInstalledList? installedListSlot;
  AddonHubInstalledList get installedList => installedListSlot!;
}
