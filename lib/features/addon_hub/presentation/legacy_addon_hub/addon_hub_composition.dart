import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_sections.dart';
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
  return sections;
}
