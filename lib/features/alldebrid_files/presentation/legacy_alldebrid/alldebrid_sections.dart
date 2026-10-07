import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_add_actions.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_delete_actions.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_downloads.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_loading.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playlist_actions.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_root_layout.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_scope.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_bars.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_toolbar.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

typedef AllDebridOwners = ({
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  AllDebridSelectionState selectionState,
  AllDebridFeedbackState feedbackState,
});

class AllDebridSections {
  AllDebridNavigation? navigationSlot;
  AllDebridNavigation get navigation => navigationSlot!;
  AllDebridLibraryLoading? libraryLoadingSlot;
  AllDebridLibraryLoading get libraryLoading => libraryLoadingSlot!;
  AllDebridPlayback? playbackSlot;
  AllDebridPlayback get playback => playbackSlot!;
  AllDebridDownloads? downloadsSlot;
  AllDebridDownloads get downloads => downloadsSlot!;
  AllDebridAddActions? addActionsSlot;
  AllDebridAddActions get addActions => addActionsSlot!;
  AllDebridDeleteActions? deleteActionsSlot;
  AllDebridDeleteActions get deleteActions => deleteActionsSlot!;
  AllDebridPlaylistActions? playlistActionsSlot;
  AllDebridPlaylistActions get playlistActions => playlistActionsSlot!;
  AllDebridSelection? selectionSlot;
  AllDebridSelection get selection => selectionSlot!;
  AllDebridSearch? searchSlot;
  AllDebridSearch get search => searchSlot!;
  AllDebridFeedback? feedbackSlot;
  AllDebridFeedback get feedback => feedbackSlot!;
  AllDebridRootLayout? rootLayoutSlot;
  AllDebridRootLayout get rootLayout => rootLayoutSlot!;
  AllDebridToolbar? toolbarSlot;
  AllDebridToolbar get toolbar => toolbarSlot!;
  AllDebridSearchBars? searchBarsSlot;
  AllDebridSearchBars get searchBars => searchBarsSlot!;
  AllDebridListViews? listViewsSlot;
  AllDebridListViews get listViews => listViewsSlot!;
}

AllDebridSections createAllDebridSections(
  AllDebridScope scope,
  AllDebridOwners owners,
) {
  final sections = AllDebridSections();
  sections.navigationSlot = AllDebridNavigation((
    navigationState: owners.navigationState,
    selectionState: owners.selectionState,
    searchState: owners.searchState,
    focusState: owners.focusState,
    libraryState: owners.libraryState,
    mounted: scope.mounted,
    setState: scope.setState,
    exitSelectionMode: () => sections.selection.exitSelectionMode(),
    focusFirstItem: () => sections.navigation.focusFirstItem(),
    isAtRoot: () => sections.navigation.isAtRoot,
    load: () => sections.libraryLoading.load(),
    loadLinks: () => sections.libraryLoading.loadLinks(),
    navigateUp: () => sections.navigation.navigateUp(),
    openMagnet: (AllDebridMagnet magnet, {bool force = false}) =>
        sections.navigation.openMagnet(magnet, force: force),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
    toggleSearch: () => sections.search.toggleSearch(),
    visibleLinks: () => sections.search.visibleLinks,
    visibleMagnets: () => sections.search.visibleMagnets,
  ));
  sections.libraryLoadingSlot = AllDebridLibraryLoading((
    libraryState: owners.libraryState,
    selectionState: owners.selectionState,
    mounted: scope.mounted,
    setState: scope.setState,
    focusFirstItem: () => sections.navigation.focusFirstItem(),
  ));
  sections.playbackSlot = AllDebridPlayback((
    libraryState: owners.libraryState,
    navigationState: owners.navigationState,
    context: scope.context,
    mounted: scope.mounted,
    dismissLoading: () => sections.feedback.dismissLoading(),
    findFirstEpisodeIndex: (List<SeriesInfo> infos) =>
        sections.playback.findFirstEpisodeIndex(infos),
    looksLikeVideo: (AllDebridFile f) => sections.playback.looksLikeVideo(f),
    playFile: (AllDebridFile file) => sections.playback.playFile(file),
    playVideos: (List<AllDebridFile> files, String collectionName) =>
        sections.playback.playVideos(files, collectionName),
    showLoading: (String message) => sections.feedback.showLoading(message),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
    unlockStart: (String apiKey, String lockedLink) =>
        sections.playback.unlockStart(apiKey, lockedLink),
  ));
  sections.downloadsSlot = AllDebridDownloads((
    libraryState: owners.libraryState,
    navigationState: owners.navigationState,
    context: scope.context,
    mounted: scope.mounted,
    dismissLoading: () => sections.feedback.dismissLoading(),
    downloadSelectedFiles:
        (
          List<Map<String, dynamic>> selected,
          List<AllDebridFile> allFiles,
          String magnetName,
        ) => sections.downloads.downloadSelectedFiles(
          selected,
          allFiles,
          magnetName,
        ),
    showLoading: (String message) => sections.feedback.showLoading(message),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
    unlockStart: (String apiKey, String lockedLink) =>
        sections.playback.unlockStart(apiKey, lockedLink),
  ));
  sections.addActionsSlot = AllDebridAddActions((
    libraryState: owners.libraryState,
    context: scope.context,
    mounted: scope.mounted,
    dismissLoading: () => sections.feedback.dismissLoading(),
    load: () => sections.libraryLoading.load(),
    loadLinks: () => sections.libraryLoading.loadLinks(),
    showLoading: (String message) => sections.feedback.showLoading(message),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
  ));
  sections.deleteActionsSlot = AllDebridDeleteActions((
    libraryState: owners.libraryState,
    selectionState: owners.selectionState,
    context: scope.context,
    mounted: scope.mounted,
    deleteLinks: (List<AllDebridLink> links, {String? title}) =>
        sections.deleteActions.deleteLinks(links, title: title),
    deleteMagnets: (List<AllDebridMagnet> magnets, {String? title}) =>
        sections.deleteActions.deleteMagnets(magnets, title: title),
    dismissLoading: () => sections.feedback.dismissLoading(),
    exitSelectionMode: () => sections.selection.exitSelectionMode(),
    load: () => sections.libraryLoading.load(),
    loadLinks: () => sections.libraryLoading.loadLinks(),
    showLoading: (String message) => sections.feedback.showLoading(message),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
  ));
  sections.playlistActionsSlot = AllDebridPlaylistActions((
    libraryState: owners.libraryState,
    navigationState: owners.navigationState,
    mounted: scope.mounted,
    dismissLoading: () => sections.feedback.dismissLoading(),
    looksLikeVideo: (AllDebridFile f) => sections.playback.looksLikeVideo(f),
    showLoading: (String message) => sections.feedback.showLoading(message),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
  ));
  sections.selectionSlot = AllDebridSelection((
    selectionState: owners.selectionState,
    setState: scope.setState,
    isAllSelected: () => sections.selection.isAllSelected,
    visibleMagnets: () => sections.search.visibleMagnets,
  ));
  sections.searchSlot = AllDebridSearch((
    searchState: owners.searchState,
    focusState: owners.focusState,
    libraryState: owners.libraryState,
    navigationState: owners.navigationState,
    mounted: scope.mounted,
    setState: scope.setState,
  ));
  sections.feedbackSlot = AllDebridFeedback((
    feedbackState: owners.feedbackState,
    context: scope.context,
    mounted: scope.mounted,
  ));
  sections.rootLayoutSlot = AllDebridRootLayout((
    focusState: owners.focusState,
    navigationState: owners.navigationState,
    searchState: owners.searchState,
    selectionState: owners.selectionState,
    libraryState: owners.libraryState,
    context: scope.context,
    mounted: scope.mounted,
    setState: scope.setState,
    buildBody: () => sections.rootLayout.buildBody(),
    buildFileSearchBar: () => sections.searchBars.buildFileSearchBar(),
    buildFilesView: () => sections.listViews.buildFilesView(),
    buildLinksView: () => sections.listViews.buildLinksView(),
    buildMagnetsView: () => sections.listViews.buildMagnetsView(),
    buildSearchBar: () => sections.searchBars.buildSearchBar(),
    buildSelectionBar: () => sections.toolbar.buildSelectionBar(),
    buildToolbar: () => sections.toolbar.buildToolbar(),
    buildViewSelectorBar: () => sections.toolbar.buildViewSelectorBar(),
    isAtRoot: () => sections.navigation.isAtRoot,
    load: () => sections.libraryLoading.load(),
    navigateUp: () => sections.navigation.navigateUp(),
  ));
  sections.toolbarSlot = AllDebridToolbar((
    navigationState: owners.navigationState,
    libraryState: owners.libraryState,
    selectionState: owners.selectionState,
    searchState: owners.searchState,
    focusState: owners.focusState,
    context: scope.context,
    isPushedRoute: scope.isPushedRoute,
    selectSourceMode: scope.selectSourceMode,
    setState: scope.setState,
    confirmDeleteAll: () => sections.deleteActions.confirmDeleteAll(),
    confirmDeleteAllLinks: () => sections.deleteActions.confirmDeleteAllLinks(),
    exitSelectionMode: () => sections.selection.exitSelectionMode(),
    handleDeleteSelected: () => sections.deleteActions.handleDeleteSelected(),
    isAllSelected: () => sections.selection.isAllSelected,
    isBrowsePush: () => sections.toolbar.isBrowsePush,
    loadLinks: () => sections.libraryLoading.loadLinks(),
    refresh: () => sections.navigation.refresh(),
    showAddLinkDialog: () => sections.addActions.showAddLinkDialog(),
    showAddMagnetDialog: () => sections.addActions.showAddMagnetDialog(),
    toggleSearch: () => sections.search.toggleSearch(),
    toggleSelectAll: () => sections.selection.toggleSelectAll(),
    toggleSelectionMode: () => sections.selection.toggleSelectionMode(),
  ));
  sections.searchBarsSlot = AllDebridSearchBars((
    searchState: owners.searchState,
    focusState: owners.focusState,
    navigationState: owners.navigationState,
    context: scope.context,
    setState: scope.setState,
    moveFocusTo: (FocusNode? target, FocusNode field) =>
        sections.search.moveFocusTo(target, field),
    searchDecoration: (String hint) =>
        sections.searchBars.searchDecoration(hint),
  ));
  sections.listViewsSlot = AllDebridListViews((
    searchState: owners.searchState,
    focusState: owners.focusState,
    selectionState: owners.selectionState,
    libraryState: owners.libraryState,
    navigationState: owners.navigationState,
    context: scope.context,
    mounted: scope.mounted,
    onSourceSelected: scope.onSourceSelected,
    selectSourceMode: scope.selectSourceMode,
    addMagnetToPlaylist: (AllDebridMagnet magnet) =>
        sections.playlistActions.addMagnetToPlaylist(magnet),
    buildFileCard: (AllDebridFile f, int index) =>
        sections.listViews.buildFileCard(f, index),
    buildLinkCard: (AllDebridLink l, int index) =>
        sections.listViews.buildLinkCard(l, index),
    buildMagnetCard: (AllDebridMagnet m, int index) =>
        sections.listViews.buildMagnetCard(m, index),
    copyLink: (AllDebridLink l) => sections.downloads.copyLink(l),
    deleteLinks: (List<AllDebridLink> links, {String? title}) =>
        sections.deleteActions.deleteLinks(links, title: title),
    deleteMagnets: (List<AllDebridMagnet> magnets, {String? title}) =>
        sections.deleteActions.deleteMagnets(magnets, title: title),
    downloadFile: (AllDebridFile file) => sections.downloads.downloadFile(file),
    downloadLink: (AllDebridLink l) => sections.downloads.downloadLink(l),
    downloadMagnet: (AllDebridMagnet magnet) =>
        sections.downloads.downloadMagnet(magnet),
    load: () => sections.libraryLoading.load(),
    loadLinks: () => sections.libraryLoading.loadLinks(),
    looksLikeVideo: (AllDebridFile f) => sections.playback.looksLikeVideo(f),
    openMagnet: (AllDebridMagnet magnet, {bool force = false}) =>
        sections.navigation.openMagnet(magnet, force: force),
    playFile: (AllDebridFile file) => sections.playback.playFile(file),
    playLink: (AllDebridLink l) => sections.playback.playLink(l),
    playMagnet: (AllDebridMagnet magnet) =>
        sections.playback.playMagnet(magnet),
    snack: (String message, {bool isError = true}) =>
        sections.feedback.snack(message, isError: isError),
    toggleSelection: (String id) => sections.selection.toggleSelection(id),
    visibleFiles: () => sections.search.visibleFiles,
    visibleLinks: () => sections.search.visibleLinks,
    visibleMagnets: () => sections.search.visibleMagnets,
  ));
  return sections;
}
