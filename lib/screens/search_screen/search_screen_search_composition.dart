import 'package:flutter/services.dart';

import '../../features/search/presentation/keyword_search_actions.dart';
import '../../features/search/presentation/lists_navigation.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/metadata_title_service.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/torrent_bulk_add_service.dart';
import '../../services/torrent_playback_service.dart';
import 'discover_composition.dart';
import 'search_presentation_composition.dart';
import 'search_screen_composer.dart';
import 'search_title_composition.dart';

/// Constructs the screen's Discover and Search presentation owners, in their original order.
void composeSearchScreenSearch(SearchScreenComposer c) {
  c.discover = createDiscover((
    mounted: () => c.mounted,
    setState: c.setState,
    context: () => c.context,
    discoverMode: () => c.widget.discoverMode,
    isTelevision: () => c.widget.isTelevision,
    bindings: () => c.discoverLifecycle.bindings,
    catalog: () => c.catalogPresentation,
    continuation: () => c.leading.content,
    board: () => c.board.workflow.boardSection,
    buildPanel: (section) => c.discoverPanels.build(section),
    mdblistEnabled: kMdblistEnabled,
  ));
  c.search = createSearchPresentation(
    c.ref,
    (
      mounted: () => c.mounted,
      setState: c.setState,
      context: () => c.context,
      isTelevision: () => c.widget.isTelevision,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      session: () => c.searchLifecycle,
      board: () => c.board,
      catalog: () => c.catalogPresentation,
      hero: () => c.hero,
      keywordAllowed: () =>
          ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
      floatingNavigation: () =>
          MainPageBridge.phoneNavStyleCached == 'floating',
      mdblistEnabled: kMdblistEnabled,
    ),
    searchController: c.searchController,
    submitFocus: c.searchSubmitFocus,
    discover: c.discover.section,
    createKeywordActions: (section, selection) => KeywordSearchActions((
      context: () => c.context,
      mounted: () => c.mounted,
      bindings: () => c.searchLifecycle.searchResultBindings,
      bulkAdd: TorrentBulkAddService.showBulkAddDialog,
      activate: TorrentPlaybackService.activateTorrent,
      canDownload: (torrent) =>
          ProfilePolicyGuard.allowsSync(ProfileFeature.downloads) &&
          TorrentPlaybackService.supportsDirectStreamDownload(torrent),
      download: TorrentPlaybackService.downloadDirectStream,
      copyText: (link) => Clipboard.setData(ClipboardData(text: link)),
      snack: (message) => c.homeActions.playback.snack(message),
      freeze: section.kwFreeze,
      selection: selection,
    )),
    trackOpen: (choice) => AnalyticsService.trackInBackground(
      'mdblist_list_search_open',
      {'liked': choice.liked},
    ),
    createNavigation: () => ListsNavigation(
      isTelevision: () => c.widget.isTelevision,
      pikpakOnly: () => c.catalogPresentation.badges.pikpakOnly,
      isBound: (item) => c.catalogPresentation.badges.isBound(item),
      onOpen: (item) => c.homeActions.items.openItem(
        item,
        c.catalogPresentation.navigation.addonForContinue(item.sourceAddon?.id),
        isMdblistSource: true,
      ),
      onQuickPlay: (item) => c.homeActions.catalog.onCatalogPlay(
        item,
        c.catalogPresentation.navigation.addonForContinue(item.sourceAddon?.id),
        isMdblistSource: true,
      ),
      afterReturn: c.leading.continuation.returning.afterSeeAllReturn,
    ),
    createTitles: (readMode) => createSearchTitles(
      (
        mounted: () => c.mounted,
        context: () => c.context,
        mode: readMode,
        searchMode: () => c.widget.searchMode,
        metadata: () =>
            c.catalogPresentation.metadata.metadataFeatureController.current,
        activeTab: () => MainPageBridge.activeTab.value,
        originCurrent: () => c.titleSearchScope == ProfileRuntime.scope.value,
        update:
            (query, {required language, enabled = true, composing = false}) =>
                c.titleSearch.update(
                  query,
                  language: language,
                  enabled: enabled,
                  composing: composing,
                ),
        clear: () => c.titleSearch.clear(),
        titles: () => c.titleSearch.value,
        resolver: () =>
            c.widget.suggestedTitleResolver ??
            MetadataTitleService.instance.resolve,
        openItem: (item, addon) => c.homeActions.items.openItem(item, addon),
      ),
      c.searchController,
      c.searchSubmitFocus,
    ),
  );
}
