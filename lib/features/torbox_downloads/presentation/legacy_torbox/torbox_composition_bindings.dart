import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';

import 'torbox_add_input_state.dart';
import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_folder_search_state.dart';
import 'torbox_navigation_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_torrent_search_state.dart';
import 'torbox_view_state.dart';
import 'torbox_web_state.dart';

/// Live State/widget access; no context or widget-value snapshot.
typedef TorboxViewBindings = ({
  StateSetter setState,
  bool Function() mounted,
  BuildContext Function() context,
  TorboxTorrent? Function() initialTorrentToOpen,
  bool Function() isPushedRoute,
  String? Function() initialSearchQuery,
  bool Function() selectSourceMode,
  void Function(SeriesSource)? Function() onSourceSelected,
});

/// Borrow the same nine owners that State constructs before mounting.
typedef TorboxCompositionStates = ({
  TorboxCatalogState catalogState,
  TorboxWebState webState,
  TorboxNavigationState navigationState,
  TorboxViewState viewState,
  TorboxFocusState focusState,
  TorboxFolderSearchState folderSearchState,
  TorboxTorrentSearchState torrentSearchState,
  TorboxSelectionState selectionState,
  TorboxAddInputState addInputState,
});
