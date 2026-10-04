import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_actions.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_loading.dart';

class AddonHubSections {
  AddonHubLoading? loadingSlot;
  AddonHubLoading get loading => loadingSlot!;
  AddonHubEngineLoading? engineLoadingSlot;
  AddonHubEngineLoading get engineLoading => engineLoadingSlot!;
  AddonHubEngineActions? engineActionsSlot;
  AddonHubEngineActions get engineActions => engineActionsSlot!;
}
