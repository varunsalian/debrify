import 'package:debrify/models/rd_file_node.dart';

/// Helper class to hold search result with its folder path
class PlaylistContentSearchResult {
  final RDFileNode node;
  final String path;

  const PlaylistContentSearchResult({required this.node, required this.path});
}
