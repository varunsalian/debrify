import 'package:flutter/material.dart';

import '../../features/home/application/home_layout_policy.dart';
import '../../features/home/data/home_catalog_repository.dart';
import '../../features/home/presentation/home_display_section.dart';
import '../../features/home/presentation/home_hero_live.dart';
import '../../features/home/presentation/home_hero_preview.dart';
import '../../features/home/presentation/home_hero_section.dart';
import '../../features/home/presentation/home_hero_shell.dart';
import '../../features/home/presentation/home_media_bindings.dart';
import '../../features/home/presentation/home_spotlight_section.dart';
import '../../features/home/presentation/home_stage_favorites.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../features/search/presentation/search_spotlight_shell.dart';
import '../../models/stremio_addon.dart';
import 'home_board_composition.dart';
import 'search_mode_composition.dart';

typedef HomeHeroCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeMediaBindings Function() media,
  VoidCallback resetStageNavigation,
  HomeStageFavorites Function() favorites,
  HomeBoardWorkflow Function() board,
  HomeCatalogRepository Function() repository,
  Future<void> Function(List<StremioMeta>, {String? sourceTitle})
  publishTopShelf,
});

typedef HomeHeroComposition = ({
  HomeHeroSection heroSection,
  HomeHeroPreview heroPreview,
  HomeHeroLive heroLive,
  HomeHeroShell heroShell,
  HomeDisplaySection displaySection,
  HomeSpotlightSection spotlightSection,
  SearchSpotlightShell spotlightShell,
});

/// Constructs hero, preview and shell owners; their original start points remain separate.
HomeHeroComposition createHomeHero(
  HomeHeroCompositionDeps deps, {
  required SearchModeComposition search,
  required SearchInputSection input,
  required TextEditingController searchController,
  required ValueNotifier<String?> ambientArt,
  required ValueNotifier<Color?> heroTint,
  required ValueNotifier<double> chromeDim,
  required ValueNotifier<bool> lightsOff,
}) {
  late final HomeHeroSection heroSection;
  late final HomeHeroPreview heroPreview;
  late final HomeHeroLive heroLive;
  late final HomeHeroShell heroShell;
  late final HomeDisplaySection displaySection;
  late final HomeSpotlightSection spotlightSection;
  late final SearchSpotlightShell spotlightShell;

  heroSection = HomeHeroSection(
    (
      media: deps.media,
      mounted: deps.mounted,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      stageActive: () => displaySection.stageActive,
      stagePublishesShellArt: () => displaySection.stagePublishesShellArt,
      clearFavoriteFocus: () => deps.favorites().canvasFavFocus.value = null,
      preview: () => heroPreview,
      clearLive: () => heroLive.clearHeroLiveIptv(),
    ),
    ambientArt,
    heroTint,
  );
  heroPreview = HomeHeroPreview((
    media: deps.media,
    mounted: deps.mounted,
    setState: deps.setState,
    context: deps.context,
    isTelevision: deps.isTelevision,
    searchMode: deps.searchMode,
    discoverMode: deps.discoverMode,
    stageActive: () => displaySection.stageActive,
    stageWantsAmbient: () => displaySection.stageWantsAmbient,
    homeStyle: () => displaySection.homeStyleEffective,
    hasFavoriteFocus: () => deps.favorites().canvasFavFocus.value != null,
    hasLiveChannel: () => heroLive.heroLiveChannel.value != null,
    spotlightHeroId: () =>
        spotlightSection.spotlightKey.currentState?.currentHeroId,
  ), heroSection.heroItem);
  heroLive = HomeHeroLive(
    (media: deps.media, mounted: deps.mounted),
    heroSection,
    heroPreview,
    ambientArt,
    heroTint,
  );
  heroShell = HomeHeroShell(heroPreview, chromeDim, lightsOff);
  displaySection = HomeDisplaySection(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      spotlightShellActive: () => spotlightShell.spotlightShellActive,
      searchSheetOpen: () => spotlightShell.searchSheetOpen,
      resetStageNavigation: deps.resetStageNavigation,
    ),
    heroSection,
    heroPreview,
    heroLive,
    ambientArt,
  );
  spotlightSection = HomeSpotlightSection((
    mounted: deps.mounted,
    setState: deps.setState,
    searchMode: deps.searchMode,
    discoverMode: deps.discoverMode,
    heroSource: () => deps.board().boardSection.heroSource,
    sections: () => deps.board().boardSection.sections,
    repository: deps.repository,
    publishTopShelf: deps.publishTopShelf,
  ), search.catalog);
  spotlightShell = SearchSpotlightShell(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      offTvSpotlightStyle: () =>
          effectiveOffTvHomeStyle(displaySection.tvHomeStyle) == 'spotlight',
      offTvSpotlightShell: () => shouldUseOffTvSpotlightShell(
        rawStyle: displaySection.tvHomeStyle,
        loading: deps.board().boardSection.loading,
        hasHero: spotlightSection.spotlightHero.isNotEmpty,
      ),
    ),
    searchController,
    input,
    search.mode,
    search.catalog,
  );
  return (
    heroSection: heroSection,
    heroPreview: heroPreview,
    heroLive: heroLive,
    heroShell: heroShell,
    displaySection: displaySection,
    spotlightSection: spotlightSection,
    spotlightShell: spotlightShell,
  );
}

/// Releases hero resources in the existing ordered media teardown protocol.
/// Shell registrations are released by the caller immediately before this phase.
void disposeHomeHeroMedia(HomeHeroComposition hero, HomeMediaBindings media) {
  media.disposeResumeAndMetadata();
  hero.heroSection.heroSwap.dispose();
  media.disposeTrailerAndTint();
  hero.heroSection.heroItem.dispose();
  hero.heroSection.heroEnriched.dispose();
  hero.heroPreview.heroTrailer.dispose();
  hero.heroPreview.heroTrailerLoading.dispose();
  hero.heroPreview.heroTrailerShowing.dispose();
  hero.heroPreview.heroTrailerTakeover.dispose();
  media.disposeLivePreview();
  hero.heroLive.heroLiveUrl.dispose();
  hero.heroLive.heroLiveChannel.dispose();
  hero.heroLive.heroLiveTakeover.dispose();
  hero.heroSection.heroTint.dispose();
}
