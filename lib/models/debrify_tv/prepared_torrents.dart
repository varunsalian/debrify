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
