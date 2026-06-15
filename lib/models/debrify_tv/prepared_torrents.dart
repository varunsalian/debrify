/// Represents a Torbox torrent that has been prepared for streaming.
///
/// Contains the stream URL, title, and whether there are more files
/// available in the torrent.
class TorboxPreparedTorrent {
  final String streamUrl;
  final String title;
  final bool hasMore;

  TorboxPreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}

/// Represents a PikPak torrent that has been prepared for streaming.
///
/// Contains the stream URL, title, and whether there are more files
/// available in the torrent.
class PikPakPreparedTorrent {
  final String streamUrl;
  final String title;
  final bool hasMore;

  PikPakPreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}

/// Represents a Premiumize torrent that has been prepared for streaming.
///
/// Premiumize returns ready-to-use direct links from directdl in one call,
/// so no separate unrestrict step is needed.
class PremiumizePreparedTorrent {
  final String streamUrl;
  final String title;
  final bool hasMore;

  PremiumizePreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}
