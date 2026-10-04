import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';

typedef AddonHubFiltersDeps = ({
  AddonHubInstalledState installedState,
  AddonHubNavigationState navigationState,
});

class AddonHubFilters {
  AddonHubFilters(this._deps);
  final AddonHubFiltersDeps _deps;

  bool isInstalled(MarketplaceAddon m) {
    // Match by manifest id OR transport URL. Note: a configurable addon installed
    // via the Configure→paste flow has a different (configured) URL than its
    // marketplace [config] transportUrl, so it's recognised only by id — fine for
    // addons that keep their id after configuration (the common case).
    for (final a in _deps.installedState.installed) {
      if (a.id == m.id || a.manifestUrl == m.transportUrl) return true;
    }
    return false;
  }

  bool matchesFilters({required List<String> types, required String name}) {
    if (_deps.navigationState.typeFilter.isNotEmpty &&
        !types.contains(_deps.navigationState.typeFilter)) {
      return false;
    }
    if (_deps.navigationState.search.isNotEmpty &&
        !name.toLowerCase().contains(
          _deps.navigationState.search.toLowerCase(),
        )) {
      return false;
    }
    return true;
  }
}
