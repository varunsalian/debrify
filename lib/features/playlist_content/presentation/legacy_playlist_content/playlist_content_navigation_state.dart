import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';

class PlaylistContentNavigationState {
  // Current navigation state
  List<String> folderPath = []; // Path segments for breadcrumbs

  List<RDFileNode>?
  currentViewNodes; // Current folder's visible nodes (after view mode transformation)

  // View mode state
  FolderViewMode currentViewMode = FolderViewMode.raw;
}
