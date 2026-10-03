import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_browsing_composition.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_composition.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_composition.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_and_selection_composition.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recordings_composition.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_composition.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_standard_layouts_composition.dart';

/// Composition only: each group and section is created once for its State.
/// Deferred cross-group getters prevent construction cycles and retain live reads.
class IptvViewSections {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;

  IptvViewSections(this._view, this._states);

  late final IptvCatalogComposition catalog =
      IptvCatalogComposition(_view, _states, (
        filtersSection: () => browsing.filtersSection,
        guideContext: () => browsing.guideContext,
        playbackRefresh: () => playback.playbackRefresh,
        previewTuning: () => previewAndSelection.previewTuning,
        rowProjection: () => previewAndSelection.rowProjection,
        sourceStatistics: () => recordings.sourceStatistics,
        virtualResults: () => browsing.virtualResults,
      ));

  late final IptvBrowsingComposition browsing =
      IptvBrowsingComposition(_view, _states, (
        catalogFacades: () => catalog.catalogFacades,
        catalogLoading: () => catalog.catalogLoading,
        catalogPresentation: () => catalog.catalogPresentation,
        loadStatus: () => catalog.loadStatus,
        previewTuning: () => previewAndSelection.previewTuning,
        rowProjection: () => previewAndSelection.rowProjection,
        spotlightFocus: () => spotlight.spotlightFocus,
        statusChip: () => catalog.statusChip,
      ));

  late final IptvPlaybackComposition playback =
      IptvPlaybackComposition(_view, _states, (
        androidRecording: () => recordings.androidRecording,
        catalogLoading: () => catalog.catalogLoading,
        favorites: () => catalog.favorites,
        filtersSection: () => browsing.filtersSection,
        playerBrowse: () => browsing.playerBrowse,
        playerPayload: () => browsing.playerPayload,
        previewTuning: () => previewAndSelection.previewTuning,
        rowProjection: () => previewAndSelection.rowProjection,
        spotlightContent: () => spotlight.spotlightContent,
        spotlightFocus: () => spotlight.spotlightFocus,
        tabletSelection: () => previewAndSelection.tabletSelection,
        virtualResults: () => browsing.virtualResults,
      ));

  late final IptvRecordingsComposition recordings =
      IptvRecordingsComposition(_view, _states, (
        catchup: () => playback.catchup,
        categoryActions: () => browsing.categoryActions,
        favorites: () => catalog.favorites,
        guideContext: () => browsing.guideContext,
        rowProjection: () => previewAndSelection.rowProjection,
        settingsLoading: () => catalog.settingsLoading,
      ));

  late final IptvStandardLayoutsComposition standardLayouts =
      IptvStandardLayoutsComposition(_view, _states, (
        androidRecording: () => recordings.androidRecording,
        catchup: () => playback.catchup,
        categoryActions: () => browsing.categoryActions,
        desktopRecording: () => recordings.desktopRecording,
        favorites: () => catalog.favorites,
        filtersSection: () => browsing.filtersSection,
        loadStatus: () => catalog.loadStatus,
        navigation: () => recordings.navigation,
        playback: () => playback.playback,
        playbackActions: () => playback.playbackActions,
        previewLayout: () => previewAndSelection.previewLayout,
        previewTuning: () => previewAndSelection.previewTuning,
        recordNow: () => recordings.recordNow,
        recordingSupport: () => recordings.recordingSupport,
        rowProjection: () => previewAndSelection.rowProjection,
        scheduleActions: () => recordings.scheduleActions,
        settingsLoading: () => catalog.settingsLoading,
        spotlightLayout: () => spotlight.spotlightLayout,
        tabletSelection: () => previewAndSelection.tabletSelection,
      ));

  late final IptvPreviewAndSelectionComposition previewAndSelection =
      IptvPreviewAndSelectionComposition(_view, _states, (
        androidRecording: () => recordings.androidRecording,
        favorites: () => catalog.favorites,
        navigation: () => recordings.navigation,
        playback: () => playback.playback,
        playbackActions: () => playback.playbackActions,
        previewHandoff: () => playback.previewHandoff,
        scheduleActions: () => recordings.scheduleActions,
      ));

  late final IptvSpotlightComposition spotlight =
      IptvSpotlightComposition(_view, _states, (
        androidRecording: () => recordings.androidRecording,
        catchup: () => playback.catchup,
        categoryActions: () => browsing.categoryActions,
        contentLayout: () => standardLayouts.contentLayout,
        desktopRecording: () => recordings.desktopRecording,
        favorites: () => catalog.favorites,
        filtersSection: () => browsing.filtersSection,
        navigation: () => recordings.navigation,
        playback: () => playback.playback,
        previewLayout: () => previewAndSelection.previewLayout,
        previewTuning: () => previewAndSelection.previewTuning,
        quietFilters: () => standardLayouts.quietFilters,
        recordNow: () => recordings.recordNow,
        recordingSupport: () => recordings.recordingSupport,
        rowProjection: () => previewAndSelection.rowProjection,
        scheduleActions: () => recordings.scheduleActions,
      ));
}
