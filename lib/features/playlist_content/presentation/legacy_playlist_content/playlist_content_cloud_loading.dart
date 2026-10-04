import 'dart:async';
import 'package:debrify/features/playlist_content/application/playlist_content_file_trees.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';

typedef PlaylistContentCloudLoadingDeps = ({
  Map<String, dynamic> Function() playlistItem,
  PlaylistContentCatalogState catalogState,
});

class PlaylistContentCloudLoading {
  PlaylistContentCloudLoading(this._deps);
  final PlaylistContentCloudLoadingDeps _deps;

  /// Load PikPak content
  Future<void> loadPikPakContent() async {
    // Get the folder/file ID
    final pikpakFileId = _deps.playlistItem()['pikpakFileId'] as String?;

    if (pikpakFileId != null) {
      // Preferred: Fetch fresh folder structure from PikPak
      _deps.catalogState.rootContent = await buildPikPakFolderTree(
        pikpakFileId,
      );
    } else {
      // Fallback: Use cached files (for old playlist items without pikpakFileId)
      final cachedFiles = _deps.playlistItem()['pikpakFiles'] as List?;
      if (cachedFiles != null && cachedFiles.isNotEmpty) {
        final files = cachedFiles.cast<Map<String, dynamic>>();
        _deps.catalogState.rootContent = buildPikPakFileTree(files);
      } else {
        throw Exception(
          'No PikPak file data found. Please remove and re-add this item to playlist.',
        );
      }
    }
  }

  /// Build folder tree from PikPak by fetching folder structure
  /// This properly preserves the folder hierarchy
  Future<RDFileNode> buildPikPakFolderTree(
    String folderId, {
    int depth = 0,
    String currentPath = '',
  }) async {
    final pikpak = PikPakApiService.instance;

    // Prevent infinite recursion or excessively deep folder structures
    const int maxDepth = 4;
    if (depth > maxDepth) {
      throw Exception(
        'Folder hierarchy too deep (max $maxDepth levels). Please reorganize your folders.',
      );
    }

    // Fetch files in this folder (non-recursive)
    final result = await pikpak.listFiles(parentId: folderId, limit: 100);
    final files = result.files;

    final List<RDFileNode> children = [];
    int fileIndex = 0;

    for (final file in files) {
      final kind = file['kind'] ?? '';
      final name = (file['name'] as String?) ?? 'Unknown';
      final fileId = file['id'] as String?;

      if (kind == 'drive#folder') {
        // Recursively build subfolder
        if (fileId != null) {
          // Build path for subfolder
          final subPath = currentPath.isEmpty ? name : '$currentPath/$name';
          final subTree = await buildPikPakFolderTree(
            fileId,
            depth: depth + 1,
            currentPath: subPath,
          );
          children.add(
            RDFileNode.folder(name: name, children: subTree.children),
          );
        }
      } else {
        // Add file node
        final sizeRaw = file['size'];
        final size = sizeRaw is int
            ? sizeRaw
            : (sizeRaw is String ? int.tryParse(sizeRaw) ?? 0 : 0);

        // Store the PikPak file metadata in the node's path field (we'll parse it later)
        // Format: "pikpak://fileId|fileName"
        final pikpakUrl = 'pikpak://$fileId|$name';

        // Build relative path for series parsing
        final relPath = currentPath.isEmpty ? name : '$currentPath/$name';

        children.add(
          RDFileNode.file(
            name: name,
            fileId: fileIndex,
            path: pikpakUrl, // Store PikPak file ID and name here
            relativePath: relPath, // Store clean path for series parsing
            bytes: size,
            linkIndex: fileIndex,
          ),
        );
        fileIndex++;
      }
    }

    return RDFileNode.folder(name: 'Root', children: children);
  }

  /// Load Premiumize content by re-resolving the torrent's files from its hash.
  Future<void> loadPremiumizeContent() async {
    final infohash = (_deps.playlistItem()['torrent_hash'] as String?)?.trim();
    if (infohash == null || infohash.isEmpty) {
      // Collection saved from the cloud browser: build the tree from stored
      // file metadata (each node carries its cloud item id for re-resolution).
      final filesRaw = _deps.playlistItem()['premiumizeFiles'];
      if (filesRaw is List && filesRaw.isNotEmpty) {
        _deps.catalogState.rootContent = buildPremiumizeCloudFileTree(filesRaw);
        return;
      }
      // Single cloud item: build a one-node tree from its metadata.
      final singleFile = _deps.playlistItem()['premiumizeFile'];
      if (singleFile is Map) {
        _deps.catalogState.rootContent = buildPremiumizeCloudFileTree([
          singleFile,
        ]);
        return;
      }
      throw Exception('No Premiumize torrent hash found');
    }

    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Premiumize API key in Settings');
    }

    final files = await PremiumizeService.resolveFilesByHash(apiKey, infohash);
    if (files.isEmpty) {
      throw Exception('No files found in torrent');
    }

    _deps.catalogState.rootContent = buildPremiumizeFileTree(files);
  }

  /// Load WebDAV content from the file metadata stored in the playlist item.
  Future<void> loadWebDavContent() async {
    final files = <Map<String, dynamic>>[];
    final singleFile = asStringDynamicMap(_deps.playlistItem()['webdavFile']);
    if (singleFile != null) {
      files.add(singleFile);
    }

    final cachedFiles = _deps.playlistItem()['webdavFiles'];
    if (cachedFiles is List) {
      for (final rawFile in cachedFiles) {
        final file = asStringDynamicMap(rawFile);
        if (file != null) files.add(file);
      }
    }

    final fallbackPath = (_deps.playlistItem()['webdavPath'] ?? '').toString();
    if (files.isEmpty && fallbackPath.isNotEmpty) {
      files.add({
        'name': fileNameFromPath(fallbackPath, fallbackPath),
        'path': fallbackPath,
        'sizeBytes': _deps.playlistItem()['sizeBytes'],
      });
    }

    if (files.isEmpty) {
      throw Exception(
        'No WebDAV file data found. Please remove and re-add this item to playlist.',
      );
    }

    _deps.catalogState.rootContent = buildWebDavFileTree(
      files,
      rootPath: (_deps.playlistItem()['webdavFolderPath'] ?? '').toString(),
    );
  }
}
