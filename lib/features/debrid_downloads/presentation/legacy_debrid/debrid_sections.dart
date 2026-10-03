import 'debrid_back_navigation.dart';
import 'debrid_catalog_loading.dart';
import 'debrid_delete_all_actions.dart';
import 'debrid_download_bulk_delete.dart';
import 'debrid_download_row_actions.dart';
import 'debrid_feedback.dart';
import 'debrid_focus_actions.dart';
import 'debrid_selected_delete.dart';
import 'debrid_selection_actions.dart';
import 'debrid_single_delete_actions.dart';
import 'debrid_torrent_bulk_delete.dart';

class DebridSections {
  late final DebridFocusActions focusActions;
  late final DebridBackNavigation backNavigation;
  late final DebridCatalogLoading catalogLoading;
  late final DebridDownloadRowActions downloadRowActions;
  late final DebridSingleDeleteActions singleDeleteActions;
  late final DebridDeleteAllActions deleteAllActions;
  late final DebridTorrentBulkDelete torrentBulkDelete;
  late final DebridDownloadBulkDelete downloadBulkDelete;
  late final DebridSelectionActions selectionActions;
  late final DebridSelectedDelete selectedDelete;
  late final DebridFeedback feedback;
}
