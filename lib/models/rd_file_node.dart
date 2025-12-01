/// Represents a file or folder node in a Real-Debrid torrent's file structure
class RDFileNode {
  final String name;
  final bool isFolder;
  final List<RDFileNode> children; // Empty if it's a file
  final int? fileId; // The file ID from RD API (null for folders)
  final String? path; // Full path from the RD API
  final int? bytes; // File size in bytes (null for folders)
  final int linkIndex; // Index in the torrent's links array for unrestricting
  final bool selected; // Whether this file was selected for download

  RDFileNode({
    required this.name,
    required this.isFolder,
    this.children = const [],
    this.fileId,
    this.path,
    this.bytes,
    required this.linkIndex,
    this.selected = true,
  });

  /// Create a folder node
  factory RDFileNode.folder({
    required String name,
    List<RDFileNode>? children,
  }) {
    return RDFileNode(
      name: name,
      isFolder: true,
      children: children ?? [],
      linkIndex: -1, // Folders don't have a link index
    );
  }

  /// Create a file node
  factory RDFileNode.file({
    required String name,
    required int fileId,
    required String path,
    required int bytes,
    required int linkIndex,
    bool selected = true,
  }) {
    return RDFileNode(
      name: name,
      isFolder: false,
      children: const [],
      fileId: fileId,
      path: path,
      bytes: bytes,
      linkIndex: linkIndex,
      selected: selected,
    );
  }

  /// Calculate total size of folder (sum of all file sizes)
  int get totalBytes {
    if (!isFolder) return bytes ?? 0;

    int total = 0;
    for (final child in children) {
      if (child.isFolder) {
        total += child.totalBytes;
      } else {
        total += child.bytes ?? 0;
      }
    }
    return total;
  }

  /// Count total files in this node (recursive for folders)
  int get fileCount {
    if (!isFolder) return 1;

    int count = 0;
    for (final child in children) {
      count += child.fileCount;
    }
    return count;
  }

  /// Get all files recursively (flattened list)
  List<RDFileNode> getAllFiles() {
    if (!isFolder) return [this];

    final files = <RDFileNode>[];
    for (final child in children) {
      if (child.isFolder) {
        files.addAll(child.getAllFiles());
      } else {
        files.add(child);
      }
    }
    return files;
  }

  /// Create a copy with modified children
  RDFileNode copyWith({
    String? name,
    bool? isFolder,
    List<RDFileNode>? children,
    int? fileId,
    String? path,
    int? bytes,
    int? linkIndex,
    bool? selected,
  }) {
    return RDFileNode(
      name: name ?? this.name,
      isFolder: isFolder ?? this.isFolder,
      children: children ?? this.children,
      fileId: fileId ?? this.fileId,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      linkIndex: linkIndex ?? this.linkIndex,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'isFolder': isFolder,
      'children': children.map((child) => child.toJson()).toList(),
      'fileId': fileId,
      'path': path,
      'bytes': bytes,
      'linkIndex': linkIndex,
      'selected': selected,
    };
  }

  factory RDFileNode.fromJson(Map<String, dynamic> json) {
    return RDFileNode(
      name: json['name'] as String,
      isFolder: json['isFolder'] as bool,
      children: (json['children'] as List<dynamic>?)
              ?.map((child) => RDFileNode.fromJson(child as Map<String, dynamic>))
              .toList() ??
          const [],
      fileId: json['fileId'] as int?,
      path: json['path'] as String?,
      bytes: json['bytes'] as int?,
      linkIndex: json['linkIndex'] as int? ?? -1,
      selected: json['selected'] as bool? ?? true,
    );
  }
}