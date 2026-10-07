import '../../models/folder_view_mode.dart';
import '../../models/premiumize_view.dart';

class PremiumizeViewState {
  // Active view (cloud files vs transfers).
  PremiumizeView selectedView = PremiumizeView.files;

  // Per-folder view-mode persistence during this session.
  final Map<String, PremiumizeFolderViewMode> folderViewModes = {};
}
