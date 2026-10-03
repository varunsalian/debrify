import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/rd_torrent.dart';

class DebridNavigationState {
  String? currentTorrentId;

  RDTorrent? currentTorrent;

  List<String> folderPath = [];

  RDFileNode? currentFolderTree;

  List<RDFileNode>? currentViewNodes;

  bool isLoadingFolder = false;
}
