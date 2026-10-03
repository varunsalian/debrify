import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';

class TorboxNavigationState {
  // Folder navigation state
  // null means we're at root (torrent list)
  TorboxTorrent? currentTorrent;

  // null means we're not viewing a web download
  TorboxWebDownload? currentWebDownload;

  // Path within current torrent/web download's folder tree
  List<String> currentPath = [];

  // Current folder node being viewed
  RDFileNode? currentFolderNode;

  final List<
    ({
      TorboxTorrent? torrent,
      TorboxWebDownload? webDownload,
      List<String> path,
      RDFileNode? node,
    })
  >
  navigationStack = [];
}
