import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';

class TorboxNavigationState {
  TorboxTorrent? currentTorrent;

  TorboxWebDownload? currentWebDownload;

  List<String> currentPath = [];

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
