import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/rd_file_node.dart';

class PlaylistContentCatalogState {
  bool isLoading = true;

  String? errorMessage;

  RDFileNode? rootContent; // Root content tree

  // AllDebrid: files in the order used to build the tree, so a node's linkIndex
  // maps to its locked link (parallels Real-Debrid's links[] array).
  List<AllDebridFile> allDebridFiles = [];
}
