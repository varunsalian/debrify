import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';

class PikpakViewState {
  final Map<String, FolderViewMode> folderViewModes = {};

  bool isInVirtualFolder = false;

  String? virtualFolderName;

  List<Map<String, dynamic>> virtualFolderFiles = [];

  final Map<String, List<Map<String, dynamic>>> recursiveFileCache = {};
}
