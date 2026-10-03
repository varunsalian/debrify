import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';

import 'pikpak_back_navigation.dart';
import 'pikpak_catalog_loading.dart';
import 'pikpak_catalog_state.dart';
import 'pikpak_delete_actions.dart';
import 'pikpak_feedback.dart';
import 'pikpak_focus_actions.dart';
import 'pikpak_focus_state.dart';
import 'pikpak_link_state.dart';
import 'pikpak_navigation_state.dart';
import 'pikpak_search_state.dart';
import 'pikpak_selection_actions.dart';
import 'pikpak_selection_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakScope = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  String? Function() initialFolderId,
  String? Function() initialFolderName,
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  Future<void> Function(SeriesSource)? Function() onSourceSelected,
});
typedef PikpakOwners = ({
  PikpakCatalogState catalogState,
  PikpakNavigationState navigationState,
  PikpakViewState viewState,
  PikpakFocusState focusState,
  PikpakSelectionState selectionState,
  PikpakSearchState searchState,
  PikpakLinkState linkState,
});
typedef PikpakDeferred = ({
  List<Map<String, dynamic>> Function(
    FolderViewMode mode,
    List<Map<String, dynamic>> items,
  )
  applyViewMode,
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>> files)
  filterFiles,
  FolderViewMode Function() getCurrentViewMode,
  void Function() navigateUpWithVirtual,
  void Function() toggleSearch,
});

class PikpakSections {
  PikpakFocusActions? focusActionsSlot;
  PikpakFocusActions get focusActions => focusActionsSlot!;
  PikpakBackNavigation? backNavigationSlot;
  PikpakBackNavigation get backNavigation => backNavigationSlot!;
  PikpakCatalogLoading? catalogLoadingSlot;
  PikpakCatalogLoading get catalogLoading => catalogLoadingSlot!;
  PikpakDeleteActions? deleteActionsSlot;
  PikpakDeleteActions get deleteActions => deleteActionsSlot!;
  PikpakSelectionActions? selectionActionsSlot;
  PikpakSelectionActions get selectionActions => selectionActionsSlot!;
  PikpakFeedback? feedbackSlot;
  PikpakFeedback get feedback => feedbackSlot!;
}
