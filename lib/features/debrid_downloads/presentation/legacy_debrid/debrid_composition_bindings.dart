import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';

import 'debrid_add_input_state.dart';
import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';
import 'debrid_focus_state.dart';
import 'debrid_folder_search_state.dart';
import 'debrid_navigation_state.dart';
import 'debrid_selection_state.dart';
import 'debrid_torrent_search_state.dart';
import 'debrid_view_state.dart';

/// Live State/widget access; no context or widget-value snapshot.
typedef DebridViewBindings = ({
  StateSetter setState,
  bool Function() mounted,
  BuildContext Function() context,
  RDTorrent? Function() initialTorrentForOptions,
  bool Function() isPushedRoute,
  String? Function() initialSearchQuery,
  bool Function() selectSourceMode,
  void Function(SeriesSource)? Function() onSourceSelected,
});

/// Borrow the same nine owners that State constructs before mounting.
typedef DebridCompositionStates = ({
  DebridCatalogState catalogState,
  DebridDownloadState downloadState,
  DebridNavigationState navigationState,
  DebridViewState viewState,
  DebridFocusState focusState,
  DebridFolderSearchState folderSearchState,
  DebridTorrentSearchState torrentSearchState,
  DebridSelectionState selectionState,
  DebridAddInputState addInputState,
});
