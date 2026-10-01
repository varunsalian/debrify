import 'package:flutter/widgets.dart';

import '../../../models/mdblist_list_choice.dart';
import '../../../models/media_server.dart';
import '../../../models/metadata_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../../../screens/media_server_library_panel.dart';
import '../../../screens/metadata_explore_page.dart';
import '../../../screens/see_all/catalog_see_all_screen.dart';
import '../../../screens/see_all/continue_watching_see_all_screen.dart';
import '../../../screens/see_all/mdblist_see_all_screen.dart';
import '../../../screens/see_all/simkl_see_all_screen.dart';
import '../../../screens/see_all/trakt_see_all_screen.dart';
import '../models/discover_source_state.dart';
import 'discover_source_panel.dart';
import 'discover_source_picker.dart';

/// Composes Discover's actual embedded panels without changing their element
/// ancestry. Only the selected panel is constructed; the host supplies current
/// data and accepted actions, and retains ownership of the shared focus node.
Widget buildDiscoverPanels({
  required String selected,
  required bool isTelevision,
  required FocusNode sourceNode,
  required MetadataPreferences? preferences,
  required bool mdblistEnabled,
  required bool mdblistAuthenticated,
  required List<StremioAddon> addons,
  required ValueChanged<String> onSelectSource,
  required bool pikpakOnly,
  required ValueChanged<StremioMeta> onItemFocused,
  required bool Function(StremioMeta) isBound,
  required StremioAddon? Function(String) findAddon,
  required StremioAddon Function(String?) addonForContinue,
  required void Function(StremioMeta, StremioAddon, {bool isMdblistSource})
  onOpenCatalog,
  required void Function(StremioMeta, StremioAddon, {bool isMdblistSource})
  onPlayCatalog,
  required List<StremioMeta> traktItems,
  required Map<String, double> Function() traktProgress,
  required ValueChanged<StremioMeta> onOpenTrakt,
  required ValueChanged<StremioMeta> onPlayTrakt,
  required List<StremioMeta> simklItems,
  required Map<String, double> simklProgress,
  required ValueChanged<StremioMeta> onOpenSimkl,
  required ValueChanged<StremioMeta> onPlaySimkl,
  required ValueChanged<StremioMeta> onOpenSimklContinuation,
  required ValueChanged<StremioMeta> onPlaySimklContinuation,
  required MdblistListChoice? mdblistList,
  required List<StremioMeta> localItems,
  required double? Function(StremioMeta) localProgress,
  required ValueChanged<StremioMeta> onOpenLocal,
  required ValueChanged<StremioMeta> onPlayLocal,
  required Future<List<StremioMeta>> Function() reloadLocal,
}) {
  final source = buildDiscoverSourcePicker(
    selected: selected,
    isTelevision: isTelevision,
    focusNode: sourceNode,
    discoveryEnabled:
        preferences?.features.contains(MetadataFeature.discovery) == true,
    mdblistEnabled: mdblistEnabled,
    mdblistAuthenticated: mdblistEnabled && mdblistAuthenticated,
    addons: addons,
    onSelected: onSelectSource,
  );

  return buildDiscoverSourcePanel(
    selected: selected,
    mediaServer: (selected) => MediaServerLibraryPanel(
      key: ValueKey(selected),
      kind: selected == DiscoverSources.jellyfin
          ? MediaServerKind.jellyfin
          : MediaServerKind.emby,
      leading: source,
      isTelevision: isTelevision,
    ),
    tmdb: preferences == null
        ? null
        : () => MetadataBrowsePage(
            key: const ValueKey('disc_tmdb'),
            title: 'TMDB',
            kind: 'discover',
            preferences: preferences,
            onOpen: (item) =>
                onOpenCatalog(item, item.sourceAddon ?? addonForContinue(null)),
            onItemFocused: onItemFocused,
            isBound: isBound,
            isTelevision: isTelevision,
            embedded: true,
            leading: source,
            leadingNode: sourceNode,
          ),
    trakt: () => TraktSeeAllScreen(
      key: const ValueKey('disc_trakt'),
      cwItems: traktItems,
      cwProgress: traktProgress(),
      onOpen: onOpenTrakt,
      onQuickPlay: pikpakOnly ? null : onPlayTrakt,
      onItemFocused: onItemFocused,
      isBound: isBound,
      isTelevision: isTelevision,
      embedded: true,
      leading: source,
      leadingNode: sourceNode,
    ),
    simkl: () => SimklSeeAllScreen(
      key: const ValueKey('disc_simkl'),
      // CW is folded in as the leading "List" option (like the Trakt source).
      // Plain open/play for the browse lists; the CW-aware handlers (resume at
      // the paused/up-next episode) apply ONLY while the CW list is showing.
      cwItems: simklItems,
      cwProgress: simklProgress,
      onOpen: onOpenSimkl,
      onQuickPlay: pikpakOnly ? null : onPlaySimkl,
      cwOnOpen: onOpenSimklContinuation,
      cwOnQuickPlay: pikpakOnly ? null : onPlaySimklContinuation,
      onItemFocused: onItemFocused,
      isBound: isBound,
      isTelevision: isTelevision,
      embedded: true,
      leading: source,
      leadingNode: sourceNode,
    ),
    // MDBList items are plain catalog titles (StremioMeta w/ imdb id), so they
    // open and quick-play through the same generic catalog paths as an addon
    // catalog item — no MDBList-specific handlers needed.
    mdblist: () => MdblistSeeAllScreen(
      key: const ValueKey('disc_mdblist'),
      initialList: mdblistList,
      onOpen: (item) => onOpenCatalog(
        item,
        addonForContinue(item.sourceAddon?.id),
        isMdblistSource: true,
      ),
      onQuickPlay: pikpakOnly
          ? null
          : (item) => onPlayCatalog(
              item,
              addonForContinue(item.sourceAddon?.id),
              isMdblistSource: true,
            ),
      onItemFocused: onItemFocused,
      isBound: isBound,
      isTelevision: isTelevision,
      embedded: true,
      leading: source,
      leadingNode: sourceNode,
    ),
    findAddon: findAddon,
    catalog: (addon, catalog) => CatalogSeeAllScreen(
      key: ValueKey('disc_${addon.id}'),
      addon: addon,
      initialCatalog: catalog,
      isTelevision: isTelevision,
      onOpenItem: (item) => onOpenCatalog(item, addon),
      onQuickPlay: pikpakOnly ? null : (item) => onPlayCatalog(item, addon),
      onItemFocused: onItemFocused,
      embedded: true,
      leading: source,
      leadingNode: sourceNode,
    ),
    continueWatching: () => ContinueWatchingSeeAllScreen(
      key: const ValueKey('disc_cw'),
      title: 'Continue Watching',
      items: localItems,
      progressOf: localProgress,
      onOpen: onOpenLocal,
      onQuickPlay: pikpakOnly ? null : onPlayLocal,
      onItemFocused: onItemFocused,
      isBound: isBound,
      isTelevision: isTelevision,
      embedded: true,
      leading: source,
      leadingNode: sourceNode,
      // Re-fetch when a detail/player route pops back so finished titles drop out
      // (the quick-play path doesn't reload localItems on its own).
      onReload: reloadLocal,
    ),
  );
}
