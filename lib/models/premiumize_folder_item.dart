import '../utils/file_utils.dart';

/// The kind of entry shown in the Premiumize cloud browser.
///
/// [folder] and [file] map to Premiumize's `/folder/list` item `type`.
/// [virtualSeason] is a client-side grouping created by the "Series Arrange"
/// view mode (mirrors the PikPak browser) and has no server-side identity.
enum PremiumizeItemType { folder, file, virtualSeason }

/// A single entry in the user's Premiumize cloud, returned by `/folder/list`.
///
/// Unlike PikPak, Premiumize's listing already hands back ready-to-use [link]
/// (direct download) and [streamLink] (HLS) for file items — no extra
/// per-file resolve call is needed to play or download.
class PremiumizeFolderItem {
  final String id;
  final String name;
  final PremiumizeItemType type;

  /// File size in bytes (0 for folders).
  final int size;

  /// Direct download URL (files only; ready to use).
  final String? link;

  /// Transcoded HLS stream URL (files only; may be absent).
  final String? streamLink;

  /// MIME type (files only; e.g. `video/x-matroska`).
  final String? mimeType;

  /// Creation time as a unix timestamp in seconds (0 if unknown).
  final int createdAt;

  /// Path relative to the scan root, set during a recursive listing so folder
  /// play/download can preserve structure (e.g. "Season 1/Episode 1.mkv").
  final String? relativePath;

  /// Season number for [PremiumizeItemType.virtualSeason] groupings.
  final int? seasonNumber;

  /// Files contained in a [PremiumizeItemType.virtualSeason] grouping.
  final List<PremiumizeFolderItem> virtualChildren;

  const PremiumizeFolderItem({
    required this.id,
    required this.name,
    required this.type,
    this.size = 0,
    this.link,
    this.streamLink,
    this.mimeType,
    this.createdAt = 0,
    this.relativePath,
    this.seasonNumber,
    this.virtualChildren = const [],
  });

  bool get isFolder => type == PremiumizeItemType.folder;
  bool get isVirtualSeason => type == PremiumizeItemType.virtualSeason;
  bool get isFile => type == PremiumizeItemType.file;

  bool get isVideo =>
      isFile &&
      (FileUtils.isVideoFile(name) ||
          (mimeType?.startsWith('video/') ?? false));

  /// Best playable URL: prefer the direct [link] (works on every player),
  /// falling back to the HLS [streamLink].
  String? get playableUrl {
    if (link != null && link!.isNotEmpty) return link;
    if (streamLink != null && streamLink!.isNotEmpty) return streamLink;
    return null;
  }

  factory PremiumizeFolderItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString() ?? 'file';
    final link = json['link']?.toString();
    final stream = json['stream_link']?.toString();
    return PremiumizeFolderItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      type: typeStr == 'folder'
          ? PremiumizeItemType.folder
          : PremiumizeItemType.file,
      size: _asInt(json['size']),
      link: (link != null && link.isNotEmpty) ? link : null,
      streamLink: (stream != null && stream.isNotEmpty) ? stream : null,
      mimeType: json['mime_type']?.toString(),
      createdAt: _asInt(json['created_at']),
    );
  }

  PremiumizeFolderItem copyWith({
    String? relativePath,
    int? seasonNumber,
    List<PremiumizeFolderItem>? virtualChildren,
  }) {
    return PremiumizeFolderItem(
      id: id,
      name: name,
      type: type,
      size: size,
      link: link,
      streamLink: streamLink,
      mimeType: mimeType,
      createdAt: createdAt,
      relativePath: relativePath ?? this.relativePath,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      virtualChildren: virtualChildren ?? this.virtualChildren,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// Result of a single `/folder/list` call.
class PremiumizeFolderListing {
  final List<PremiumizeFolderItem> items;
  final String? folderName;
  final String? parentId;

  const PremiumizeFolderListing({
    required this.items,
    this.folderName,
    this.parentId,
  });
}
