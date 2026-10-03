import 'package:debrify/features/torbox_downloads/presentation/folder_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';

class TorboxViewState {
  final Map<int, FolderViewMode> torrentViewModes = {};

  final Map<int, FolderViewMode> webDownloadViewModes = {};

  List<RDFileNode>? currentViewNodes;
}
