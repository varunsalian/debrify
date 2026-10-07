import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';

import '../../models/folder_view_mode.dart';
import 'premiumize_back_navigation.dart';
import 'premiumize_catalog_loading.dart';
import 'premiumize_catalog_state.dart';
import 'premiumize_delete_actions.dart';
import 'premiumize_feedback.dart';
import 'premiumize_focus_actions.dart';
import 'premiumize_focus_state.dart';
import 'premiumize_link_state.dart';
import 'premiumize_navigation_state.dart';
import 'premiumize_search_state.dart';
import 'premiumize_selection_actions.dart';
import 'premiumize_selection_state.dart';
import 'premiumize_transfer_actions.dart';
import 'premiumize_view_state.dart';

typedef PremiumizeScope = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  String? Function() initialFolderId,
  String? Function() initialFolderName,
  String? Function() initialSearchQuery,
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  Future<void> Function(SeriesSource)? Function() onSourceSelected,
  void Function(String query) performSearch,
  PremiumizeFolderViewMode Function() getCurrentViewMode,
  List<PremiumizeFolderItem> Function(
    PremiumizeFolderViewMode mode,
    List<PremiumizeFolderItem> items,
  )
  applyViewMode,
  void Function() toggleSearch,
  void Function() navigateUp,
});
typedef PremiumizeOwners = ({
  PremiumizeCatalogState catalogState,
  PremiumizeNavigationState navigationState,
  PremiumizeViewState viewState,
  PremiumizeFocusState focusState,
  PremiumizeSelectionState selectionState,
  PremiumizeSearchState searchState,
  PremiumizeLinkState linkState,
});

class PremiumizeSections {
  PremiumizeSelectionActions? selectionActionsSlot;
  PremiumizeSelectionActions get selectionActions => selectionActionsSlot!;
  PremiumizeCatalogLoading? catalogLoadingSlot;
  PremiumizeCatalogLoading get catalogLoading => catalogLoadingSlot!;
  PremiumizeBackNavigation? backNavigationSlot;
  PremiumizeBackNavigation get backNavigation => backNavigationSlot!;
  PremiumizeDeleteActions? deleteActionsSlot;
  PremiumizeDeleteActions get deleteActions => deleteActionsSlot!;
  PremiumizeTransferActions? transferActionsSlot;
  PremiumizeTransferActions get transferActions => transferActionsSlot!;
  PremiumizeFeedback? feedbackSlot;
  PremiumizeFeedback get feedback => feedbackSlot!;
  PremiumizeFocusActions? focusActionsSlot;
  PremiumizeFocusActions get focusActions => focusActionsSlot!;
}
