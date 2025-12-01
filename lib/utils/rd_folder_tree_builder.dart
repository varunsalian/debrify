import '../models/rd_file_node.dart';
import '../utils/file_utils.dart';

class RDFolderTreeBuilder {
  /// Build a folder tree from Real-Debrid torrent info files array
  /// Each file has: {id, path, bytes, selected}
  /// Path format: "/folder1/folder2/filename.ext"
  /// Only files with selected == 1 are included in the tree
  static RDFileNode buildTree(List<Map<String, dynamic>> files) {
    // Create root node
    final rootNode = RDFileNode.folder(name: 'Root', children: []);

    // Filter out unselected files first
    // Only files with selected == 1 have corresponding links in the links array
    final selectedFiles = files.where((file) {
      final selectedValue = file['selected'];
      return selectedValue == 1 || selectedValue == true;
    }).toList();

    // Track linkIndex counter for selected files
    int linkIndexCounter = 0;

    for (final file in selectedFiles) {
      final pathValue = file['path'];
      final path = pathValue != null ? pathValue.toString() : '';
      final fileId = file['id'] as int?;
      final bytes = _parseBytes(file['bytes']);

      if (path.isEmpty) continue;

      // Split path into segments and remove empty ones
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) continue;

      // Navigate through the tree, creating folders as needed
      RDFileNode currentNode = rootNode;

      for (int i = 0; i < segments.length - 1; i++) {
        final folderName = segments[i];

        // Check if folder already exists in children
        RDFileNode? existingFolder;
        for (final child in currentNode.children) {
          if (child.isFolder && child.name == folderName) {
            existingFolder = child;
            break;
          }
        }

        if (existingFolder != null) {
          currentNode = existingFolder;
        } else {
          // Create new folder
          final newFolder = RDFileNode.folder(name: folderName, children: []);
          currentNode.children.add(newFolder);
          currentNode = newFolder;
        }
      }

      // Add the file to the current folder
      // linkIndex matches the order in the API's selected files list
      final fileName = segments.last;
      final fileNode = RDFileNode.file(
        name: fileName,
        fileId: fileId ?? 0,
        path: path,
        bytes: bytes,
        linkIndex: linkIndexCounter++, // Assign index in API order
        selected: true, // All files in tree are selected
      );
      currentNode.children.add(fileNode);
    }

    return rootNode;
  }

  /// Parse bytes value from various formats
  static int _parseBytes(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  /// Recursively collect all video files from a node
  static List<RDFileNode> collectVideoFiles(RDFileNode node) {
    final videoFiles = <RDFileNode>[];

    if (!node.isFolder) {
      // Check if this file is a video
      if (FileUtils.isVideoFile(node.name)) {
        videoFiles.add(node);
      }
    } else {
      // Recursively collect from children
      for (final child in node.children) {
        videoFiles.addAll(collectVideoFiles(child));
      }
    }

    return videoFiles;
  }

  /// Recursively collect all files from a node
  static List<RDFileNode> collectAllFiles(RDFileNode node) {
    final allFiles = <RDFileNode>[];

    if (!node.isFolder) {
      allFiles.add(node);
    } else {
      // Recursively collect from children
      for (final child in node.children) {
        allFiles.addAll(collectAllFiles(child));
      }
    }

    return allFiles;
  }

  /// Get node at specific path
  static RDFileNode? getNodeAtPath(RDFileNode root, List<String> pathSegments) {
    if (pathSegments.isEmpty) return root;

    RDFileNode currentNode = root;

    for (final segment in pathSegments) {
      // Find child with matching name
      RDFileNode? found;
      for (final child in currentNode.children) {
        if (child.name == segment) {
          found = child;
          break;
        }
      }

      if (found == null) {
        return null; // Path not found
      }
      currentNode = found;
    }

    return currentNode;
  }

  /// Count files in a node (recursive for folders)
  static int countFiles(RDFileNode node) {
    if (!node.isFolder) return 1;

    int count = 0;
    for (final child in node.children) {
      count += countFiles(child);
    }
    return count;
  }

  /// Count video files in a node
  static int countVideoFiles(RDFileNode node) {
    return collectVideoFiles(node).length;
  }

  /// Check if node contains any video files
  static bool hasVideoFiles(RDFileNode node) {
    if (!node.isFolder) {
      return FileUtils.isVideoFile(node.name);
    }

    for (final child in node.children) {
      if (hasVideoFiles(child)) return true;
    }

    return false;
  }

  /// Create a flattened root for torrents with files at root level
  /// If all files are at root level (no folders), return them directly
  /// Otherwise return the root node's children
  static List<RDFileNode> getRootLevelNodes(RDFileNode root) {
    // Check if all children are files (no folders)
    final hasOnlyFiles = root.children.every((child) => !child.isFolder);

    if (hasOnlyFiles || root.children.isEmpty) {
      // Return the children directly (all files at root)
      return root.children;
    }

    // Mix of files and folders, or only folders - return as is
    return root.children;
  }
}