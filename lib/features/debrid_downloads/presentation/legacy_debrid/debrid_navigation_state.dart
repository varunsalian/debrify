import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/rd_torrent.dart';

class DebridNavigationState {
  // Folder navigation state
  String? currentTorrentId;

  RDTorrent? currentTorrent;

  // e.g., ["Season 1", "Episodes"]
  List<String> folderPath = [];

  RDFileNode? currentFolderTree;

  // Current folder contents
  List<RDFileNode>? currentViewNodes;

  bool isLoadingFolder = false;
}
