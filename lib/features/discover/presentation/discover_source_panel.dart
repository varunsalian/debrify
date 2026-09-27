import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../models/discover_source_state.dart';

/// Selects exactly one embedded panel without adding an element or owning it.
/// Builders retain their source-specific data, action and navigation contracts.
/// Inventory lookup is synchronous and borrowed from the host's current map.
Widget buildDiscoverSourcePanel({
  required String selected,
  required Widget Function(String source) mediaServer,
  required Widget Function()? tmdb,
  required Widget Function() trakt,
  required Widget Function() simkl,
  required Widget Function() mdblist,
  required StremioAddon? Function(String id) findAddon,
  required Widget Function(StremioAddon addon, StremioAddonCatalog catalog)
  catalog,
  required Widget Function() continueWatching,
}) {
  if (selected == DiscoverSources.jellyfin ||
      selected == DiscoverSources.emby) {
    return mediaServer(selected);
  }
  if (selected == DiscoverSources.tmdb && tmdb != null) return tmdb();
  if (selected == DiscoverSources.trakt) return trakt();
  if (selected == DiscoverSources.simkl) return simkl();
  if (selected == DiscoverSources.mdblist) return mdblist();

  if (selected.startsWith(DiscoverSources.addonPrefix)) {
    final addon = findAddon(
      selected.substring(DiscoverSources.addonPrefix.length),
    );
    final initialCatalog = addon?.catalogs
        .cast<StremioAddonCatalog?>()
        .firstWhere(
          (entry) => entry != null && entry.isBrowsable,
          orElse: () => null,
        );
    if (addon != null && initialCatalog != null) {
      return catalog(addon, initialCatalog);
    }
  }
  // Missing/unbrowsable addons and TMDB without hydrated preferences keep the
  // original Continue Watching fallback; selection itself is not rewritten.
  return continueWatching();
}
