import 'package:flutter/material.dart';

import '../../features/discover/presentation/discover_session_lifecycle.dart';
import '../../services/hide_watched_prefs.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/metadata_preferences_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/profiles/profile_session_memory.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/tv_hero_artwork_quality_controller.dart';
import 'discover_panel_composition.dart';
import 'home_content_startup.dart';
import 'home_media_composition.dart';
import 'home_view_bindings.dart';
import 'search_profile_handoff.dart';
import 'search_screen_composer.dart';
import 'search_session_lifecycle.dart';

/// Constructs the screen's session, media, view bindings, startup and Discover lifecycle owners, in their original order.
void composeSearchScreenSession(SearchScreenComposer c) {
  c.profileHandoff = SearchProfileHandoff(
    () => !c.profileCurrent(),
    c.searchController,
    c.search.modes.title,
    c.search.keyword.keywordSection,
    c.search.modes.lists,
    c.search.modes.catalog,
    c.board.workflow.boardRows,
  );
  c.mediaComposition = HomeMediaComposition(
    (
      artworkWidth: () =>
          TvHeroArtworkQualityController.decodeSize.landscapeWidth,
      artworkHeight: () =>
          TvHeroArtworkQualityController.decodeSize.posterHeight,
      isTelevision: () => c.widget.isTelevision,
      isAddonChannel: StremioIptvService.isStremioChannelUrl,
    ),
    c.hero,
    c.board.stages.stageFavorites,
  );
  c.searchLifecycle = SearchSessionLifecycle(
    c.ref,
    (
      mounted: () => c.mounted,
      isTelevision: () => c.widget.isTelevision,
      setState: c.setState,
    ),
    c.search.keyword.keywordSection,
    c.search.returning,
    c.board.workflow.boardRows,
    c.board.workflow.boardPaging,
    c.searchSubmitFocus,
  );
  c.homeView = HomeViewBindings(
    c.ref,
    (
      mounted: () => c.mounted,
      setState: c.setState,
      isTelevision: () => c.widget.isTelevision,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      hideWatched: () => HideWatchedPrefs.enabled,
      search: () => c.searchLifecycle,
    ),
    c.initialHomeConfiguration,
    c.board.workflow.boardSection,
    c.board.workflow.boardConfiguration,
    c.hero.displaySection,
    c.hero.heroPreview,
  );
  c.contentStartup = HomeContentStartup(
    (
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      isTelevision: () => c.widget.isTelevision,
    ),
    c.board.workflow,
    c.catalogPresentation,
    c.discover.loading,
    c.homeView,
    c.homeReturn,
    c.leading.content.loading,
    c.leading.saved.section,
    c.search.keyword.keywordSection,
  );
  c.discoverPanels = DiscoverPanelComposition(
    (
      mounted: () => c.mounted,
      isTelevision: () => c.widget.isTelevision,
      mdblistEnabled: kMdblistEnabled,
    ),
    c.catalogPresentation.metadata,
    c.catalogPresentation.integrations,
    c.catalogPresentation.badges,
    c.board.workflow.boardSection,
    c.catalogPresentation.navigation,
    c.homeActions,
    c.leading.content,
    c.leading.playback,
  );
  c.discoverLifecycle = DiscoverSessionLifecycle(c.ref, (
    mounted: () => c.mounted,
    discoverMode: () => c.widget.discoverMode,
    owner: () => c.searchLifecycle.profileSessionOwner,
  ), c.discover.section);
  c.titleSearch.addListener(c.search.modes.title.publishTitleSuggestions);
  c.searchController.addListener(
    c.search.modes.title.onTitleSearchEditingChanged,
  );
  ProfileRuntime.scope.addListener(c.profileHandoff.onSearchProfileChanged);
  MetadataPreferencesService.revision.addListener(
    c.catalogPresentation.metadata.metadataSettingsChanged,
  );
  c.catalogPresentation.metadata.start((
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  ));
  WidgetsBinding.instance.addObserver(c.host.observer);
  c.searchLifecycle.profileSessionOwner = ProfileSessionMemory.captureOwner();
  c.homeView.initializeRepositories();
}
