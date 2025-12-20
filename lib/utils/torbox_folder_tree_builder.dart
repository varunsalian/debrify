import 'package:flutter/foundation.dart';
import '../models/rd_file_node.dart';
import '../models/torbox_file.dart';
import '../utils/file_utils.dart';

/// Builds a folder tree from Torbox's flat file list
/// Torbox files have paths in the `name` field like:
/// - "Jackie_Chan_Adventures.../S01/S01_E01.mp4"
/// - "Dark.../Season 1/Episode 01.mkv"
/// The "..." separator divides the torrent name from the folder structure
class TorboxFolderTreeBuilder {
  /// Build a folder tree from Torbox files array
  /// Files have a `name` field that may contain full paths like:
  /// "TorrentName.../FolderName/FileName.ext"
  ///
  /// Returns a root node containing all folders and files
  static RDFileNode buildTree(List<TorboxFile> files) {
    // Log input for debugging
    debugPrint('🔧 TorboxFolderTreeBuilder: Building tree from ${files.length} files');

    // Create root node
    final rootNode = RDFileNode.folder(name: 'Root', children: []);

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final name = file.name;

      // Log first 5 files to trace paths
      if (i < 5) {
        debugPrint('  File[$i]: name="$name"');
      }

      if (name.isEmpty) continue;

      // Parse the path from the name field
      // Torbox paths can be:
      // 1. "File.mkv" (single file at root)
      // 2. "Folder/File.mkv" (file in folder)
      // 3. "TorrentName.../Folder/File.mkv" (file in folder, with torrent name prefix)
      final pathSegments = _parsePathSegments(name);

      // Log parsed segments for first 3 files
      if (i < 3) {
        debugPrint('    Parsed segments: $pathSegments');
      }

      if (pathSegments.isEmpty) continue;

      // Navigate through the tree, creating folders as needed
      RDFileNode currentNode = rootNode;

      // All segments except the last are folders
      for (int j = 0; j < pathSegments.length - 1; j++) {
        final folderName = pathSegments[j];

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
      final fileName = pathSegments.last;

      // Build relative path from segments (without torrent name prefix)
      // Example: pathSegments = ["Season 1", "Episode 1.mkv"] -> "Season 1/Episode 1.mkv"
      String relativePath = pathSegments.join('/');

      final fileNode = RDFileNode.file(
        name: fileName,
        fileId: file.id,
        path: name, // Store original full path
        relativePath: relativePath,
        bytes: file.size,
        linkIndex: i, // Use the index in the files array
        selected: true,
      );
      currentNode.children.add(fileNode);
    }

    return rootNode;
  }

  /// Parse path segments from Torbox file name
  /// Handles both "/" separators and "..." torrent name separator
  static List<String> _parsePathSegments(String name) {
    // First, check if there's a "..." separator (torrent name prefix)
    // Example: "TorrentName.../Folder/File.mkv"
    String pathPart = name;

    if (name.contains('.../')) {
      // Split by "..." and take everything after it
      final parts = name.split('.../');
      if (parts.length > 1) {
        pathPart = parts.skip(1).join('.../'); // Rejoin in case there are multiple "..."
      }
    }

    // Now split by "/" to get folders and file
    final segments = pathPart.split('/').where((s) => s.isNotEmpty).toList();

    return segments;
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

  /// Get root level nodes (children of root)
  /// If all children are files (no folders), return them directly
  /// Otherwise return the children as is (mix of files and folders)
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
