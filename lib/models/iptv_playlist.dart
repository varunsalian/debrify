// IPTV Playlist and Channel models for M3U support

/// Represents an IPTV M3U playlist
class IptvPlaylist {
  final String id;
  final String name;
  final String url;
  final DateTime addedAt;

  const IptvPlaylist({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'addedAt': addedAt.toIso8601String(),
  };

  factory IptvPlaylist.fromJson(Map<String, dynamic> json) => IptvPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IptvPlaylist &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Represents an IPTV channel from an M3U playlist
class IptvChannel {
  final String name;
  final String url;
  final String? logoUrl;
  final String? group; // Category/group
  final int? duration; // -1 for live streams
  final Map<String, String> attributes; // Additional tvg-* attributes

  const IptvChannel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.group,
    this.duration,
    this.attributes = const {},
  });

  /// Check if this is a live stream (no duration or -1 duration)
  bool get isLive => duration == null || duration == -1;

  /// Get tvg-id attribute if present
  String? get tvgId => attributes['tvg-id'];

  /// Get tvg-name attribute if present
  String? get tvgName => attributes['tvg-name'];

  @override
  String toString() => 'IptvChannel(name: $name, group: $group, url: $url)';
}

/// Result of parsing an M3U playlist
class IptvParseResult {
  final List<IptvChannel> channels;
  final List<String> categories;
  final String? error;

  const IptvParseResult({
    required this.channels,
    required this.categories,
    this.error,
  });

  bool get hasError => error != null;
  bool get isEmpty => channels.isEmpty;
}
