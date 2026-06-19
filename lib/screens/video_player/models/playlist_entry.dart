class PlaylistEntry {
  final String url;
  final String title;
  // High-res YouTube: a video-only track ([hdVideoUrl]) plus a separate
  // [audioUrl], merged at playback. When set, [url] should be a muxed stream
  // (already has audio) used as the never-silent fallback.
  final String? hdVideoUrl;
  final String? audioUrl;
  final String? relativePath; // Full relative path from torrent root (e.g. "/Season 1/Episode 1.mkv")
  final String? restrictedLink; // The original restricted link from debrid
  final String? torrentHash; // SHA1 Hash of the torrent
  final int? sizeBytes; // Original file size in bytes, when known
  final String?
  provider; // Source provider identifier (e.g. realdebrid, torbox, pikpak)
  final int? torboxTorrentId; // Torbox torrent identifier for lazy resolution
  final int? torboxWebDownloadId; // Torbox web download identifier for lazy resolution
  final int? torboxFileId; // Torbox file identifier for lazy resolution
  final String? pikpakFileId; // PikPak file identifier for lazy resolution
  final String? rdTorrentId; // Real-Debrid torrent ID for lazy resolution
  final int? rdLinkIndex; // Real-Debrid link index for file in torrent
  final String? premiumizeHash; // Premiumize torrent infohash for lazy resolution
  final String? premiumizePath; // Premiumize file path (matched on re-resolve)
  final String? premiumizeItemId; // Premiumize cloud item id (lazy resolution from cloud browser)
  final String? allDebridLink; // AllDebrid locked link, unlocked on demand (lazy resolution)
  const PlaylistEntry({
    required this.url,
    required this.title,
    this.hdVideoUrl,
    this.audioUrl,
    this.relativePath,
    this.restrictedLink,
    this.torrentHash,
    this.sizeBytes,
    this.provider,
    this.torboxTorrentId,
    this.torboxWebDownloadId,
    this.torboxFileId,
    this.pikpakFileId,
    this.rdTorrentId,
    this.rdLinkIndex,
    this.premiumizeHash,
    this.premiumizePath,
    this.premiumizeItemId,
    this.allDebridLink,
  });
}
