import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';

// View mode state (per-folder persistence during session)
// Virtual folder navigation for Series Arrange mode
// e.g., "Season 1"
// Files in virtual Season
// Cache for recursive file listings (avoid repeated API calls)
class PikpakViewState {
  final Map<String, FolderViewMode> folderViewModes = {};

  bool isInVirtualFolder = false;

  String? virtualFolderName;

  List<Map<String, dynamic>> virtualFolderFiles = [];

  final Map<String, List<Map<String, dynamic>>> recursiveFileCache = {};
}
