import 'package:debrify/models/premiumize_file.dart';
import 'package:debrify/models/rd_file_node.dart';

/// Build file tree from PikPak files (from recursive list)
/// Used as fallback for old playlist items without pikpakFileId
/// Displays as a flat list since we don't have folder structure info
RDFileNode buildPikPakFileTree(List<Map<String, dynamic>> files) {
  final List<RDFileNode> nodes = [];

  for (int i = 0; i < files.length; i++) {
    final file = files[i];
    final kind = file['kind'] ?? '';
    final name = (file['name'] as String?) ?? 'Unknown';
    final fileId = file['id'] as String?;

    // PikPak returns size as String, need to parse it
    final sizeRaw = file['size'];
    final size = sizeRaw is int
        ? sizeRaw
        : (sizeRaw is String ? int.tryParse(sizeRaw) ?? 0 : 0);

    if (kind == 'drive#folder') {
      // Skip folders in flat view since we don't have hierarchy
      continue;
    } else if (fileId != null) {
      // Add file node with pikpak:// URL for playback
      final pikpakUrl = 'pikpak://$fileId|$name';

      nodes.add(
        RDFileNode.file(
          name: name,
          fileId: i,
          path: pikpakUrl, // Store PikPak file ID for playback
          bytes: size,
          linkIndex: i,
        ),
      );
    }
  }

  return RDFileNode.folder(name: 'Root', children: nodes);
}

/// Build a flat tree from cloud-browser collection metadata. Each node stores
/// the Premiumize cloud item id in its [RDFileNode.path] so playback can
/// re-resolve a fresh direct link via `/item/details`.
RDFileNode buildPremiumizeCloudFileTree(List<dynamic> filesRaw) {
  final List<RDFileNode> nodes = [];
  int i = 0;
  for (final raw in filesRaw) {
    if (raw is! Map) continue;
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final name = raw['name']?.toString() ?? 'File $id';
    final size = int.tryParse(raw['size']?.toString() ?? '') ?? 0;
    nodes.add(
      RDFileNode.file(
        name: name,
        fileId: i,
        path: id, // cloud item id, used to re-resolve on playback
        relativePath: name,
        bytes: size,
        linkIndex: i,
      ),
    );
    i++;
  }
  return RDFileNode.folder(name: 'Root', children: nodes);
}

/// Build a flat file tree from Premiumize files. Each file node stores the
/// Premiumize file path so playback can re-resolve a fresh direct link.
RDFileNode buildPremiumizeFileTree(List<PremiumizeFile> files) {
  final List<RDFileNode> nodes = [];
  for (int i = 0; i < files.length; i++) {
    final file = files[i];
    // Strip the first folder level (torrent name) for a clean series path.
    String relativePath = file.path;
    final firstSlash = relativePath.indexOf('/');
    if (firstSlash > 0) {
      relativePath = relativePath.substring(firstSlash + 1);
    }
    nodes.add(
      RDFileNode.file(
        name: file.fileName,
        fileId: i,
        path: file.path, // Premiumize file path, matched on re-resolve
        relativePath: relativePath,
        bytes: file.size,
        linkIndex: i,
      ),
    );
  }
  return RDFileNode.folder(name: 'Root', children: nodes);
}

RDFileNode buildWebDavFileTree(
  List<Map<String, dynamic>> files, {
  required String rootPath,
}) {
  final rootChildren = <RDFileNode>[];
  var fileIndex = 0;

  for (final file in files) {
    final path = (file['path'] ?? '').toString();
    if (path.isEmpty) continue;

    final fallbackName = fileNameFromPath(path, path);
    final name = ((file['name'] ?? '').toString().trim().isNotEmpty)
        ? file['name'].toString()
        : fallbackName;
    final relativePath = relativeWebDavPath(rootPath, path, name);
    final segments = relativePath
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    final safeSegments = segments.isEmpty ? [name] : segments;
    var currentChildren = rootChildren;

    for (final folderName in safeSegments.take(safeSegments.length - 1)) {
      final existingIndex = currentChildren.indexWhere(
        (node) => node.isFolder && node.name == folderName,
      );
      RDFileNode folder;
      if (existingIndex == -1) {
        folder = RDFileNode.folder(name: folderName, children: <RDFileNode>[]);
        currentChildren.add(folder);
      } else {
        folder = currentChildren[existingIndex];
      }
      currentChildren = folder.children;
    }

    final fileName = safeSegments.last;
    currentChildren.add(
      RDFileNode.file(
        name: fileName,
        fileId: fileIndex,
        path: path,
        relativePath: relativePath,
        bytes: asInt(file['sizeBytes']) ?? 0,
        linkIndex: fileIndex,
      ),
    );
    fileIndex++;
  }

  if (rootChildren.isEmpty) {
    throw Exception('No playable WebDAV files found');
  }

  return RDFileNode.folder(name: 'Root', children: rootChildren);
}

String relativeWebDavPath(String rootPath, String filePath, String name) {
  final normalizedRoot = rootPath.replaceFirst(RegExp(r'/+$'), '');
  final normalizedFile = filePath.replaceFirst(RegExp(r'/+$'), '');
  if (normalizedRoot.isNotEmpty &&
      normalizedFile.startsWith('$normalizedRoot/')) {
    return normalizedFile.substring(normalizedRoot.length + 1);
  }
  return normalizedFile.isNotEmpty ? normalizedFile : name;
}

String fileNameFromPath(String path, String fallback) {
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? fallback : parts.last;
}

Map<String, dynamic>? asStringDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

int? asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
