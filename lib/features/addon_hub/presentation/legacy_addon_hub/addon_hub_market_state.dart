import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';

class AddonHubMarketState {
  final marketplace = StremioMarketplaceService.instance;

  // Marketplace addons (Official / Community).
  List<MarketplaceAddon> market = const [];

  bool marketLoading = false;

  String? marketError;

  AddonHubSource? marketLoadedFor; // which source _market currently holds
}
