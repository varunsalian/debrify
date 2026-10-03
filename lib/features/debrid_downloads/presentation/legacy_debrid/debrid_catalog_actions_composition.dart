import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_back_navigation.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_catalog_loading.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_delete_all_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_bulk_delete.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_download_row_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_feedback.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_focus_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selected_delete.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_selection_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_single_delete_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_bulk_delete.dart';

import 'debrid_composition_bindings.dart';

void wireDebridCatalogActions(
  DebridSections sections,
  DebridViewBindings view,
  DebridCompositionStates states,
) {
  sections.focusActions = DebridFocusActions((
    focusState: states.focusState,
    mounted: view.mounted,
    navigationState: states.navigationState,
    catalogState: states.catalogState,
    downloadState: states.downloadState,
  ));
  sections.backNavigation = DebridBackNavigation((
    context: view.context,
    selectionState: states.selectionState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    folderSearchState: states.folderSearchState,
    toggleSearch: () => sections.folderSearch.toggleSearch(),
    navigationState: states.navigationState,
    navigateUp: () => sections.folderNavigation.navigateUp(),
    selectSourceMode: view.selectSourceMode,
    isPushedRoute: view.isPushedRoute,
    initialTorrentForOptions: view.initialTorrentForOptions,
  ));
  sections.catalogLoading = DebridCatalogLoading((
    focusState: states.focusState,
    catalogState: states.catalogState,
    downloadState: states.downloadState,
    mounted: view.mounted,
    setState: view.setState,
    submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
    initialSearchQuery: view.initialSearchQuery,
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
  ));
  sections.downloadRowActions = DebridDownloadRowActions((
    catalogState: states.catalogState,
    copyToClipboard: (String text) => sections.feedback.copyToClipboard(text),
    mounted: view.mounted,
    context: view.context,
    showError: (String message) => sections.feedback.showError(message),
  ));
  sections.singleDeleteActions = DebridSingleDeleteActions((
    catalogState: states.catalogState,
    context: view.context,
    mounted: view.mounted,
    setState: view.setState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    downloadState: states.downloadState,
  ));
  sections.deleteAllActions = DebridDeleteAllActions((
    catalogState: states.catalogState,
    context: view.context,
    mounted: view.mounted,
    showDeleteAllProgressDialog: () =>
        sections.torrentBulkDelete.showDeleteAllProgressDialog(),
    downloadState: states.downloadState,
    showDeleteAllDownloadsProgressDialog: () =>
        sections.downloadBulkDelete.showDeleteAllDownloadsProgressDialog(),
  ));
  sections.torrentBulkDelete = DebridTorrentBulkDelete((
    context: view.context,
    catalogState: states.catalogState,
    mounted: view.mounted,
    fetchTorrents: (String apiKey, {bool reset = false}) =>
        sections.catalogLoading.fetchTorrents(apiKey, reset: reset),
    setState: view.setState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
  ));
  sections.downloadBulkDelete = DebridDownloadBulkDelete((
    context: view.context,
    catalogState: states.catalogState,
    mounted: view.mounted,
    fetchDownloads: (String apiKey, {bool reset = false}) =>
        sections.catalogLoading.fetchDownloads(apiKey, reset: reset),
    setState: view.setState,
    downloadState: states.downloadState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
  ));
  sections.selectionActions = DebridSelectionActions((
    catalogState: states.catalogState,
    selectionState: states.selectionState,
    downloadState: states.downloadState,
    setState: view.setState,
    context: view.context,
    mounted: view.mounted,
    showDeleteSelectedProgressDialog: (Set<String> ids, bool isTorrents) =>
        sections.selectedDelete.showDeleteSelectedProgressDialog(
          ids,
          isTorrents,
        ),
  ));
  sections.selectedDelete = DebridSelectedDelete((
    context: view.context,
    catalogState: states.catalogState,
    mounted: view.mounted,
    setState: view.setState,
    downloadState: states.downloadState,
    selectionState: states.selectionState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
  ));
  sections.feedback = DebridFeedback((context: view.context));
}
