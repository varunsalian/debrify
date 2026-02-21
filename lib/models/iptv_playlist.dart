// IPTV Playlist and Channel models for M3U support

/// Represents an IPTV M3U playlist
class IptvPlaylist {
  final String id;
  final String name;
  final String url;
  final String? content; // Raw M3U content for file-based playlists
  final String? serverUrl;  // Xtream Codes server URL
  final String? username;   // Xtream Codes username
  final String? password;   // Xtream Codes password
  final DateTime addedAt;

  const IptvPlaylist({
    required this.id,
    required this.name,
    required this.url,
    this.content,
    this.serverUrl,
    this.username,
    this.password,
    required this.addedAt,
  });

  /// Returns true if this playlist was imported from a local file
  bool get isLocalFile => content != null && content!.isNotEmpty;

  /// Returns true if this is an Xtream Codes playlist
  bool get isXtreamCodes => serverUrl != null && serverUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    if (content != null) 'content': content,
    if (serverUrl != null) 'serverUrl': serverUrl,
    if (username != null) 'username': username,
    if (password != null) 'password': password,
    'addedAt': addedAt.toIso8601String(),
  };

  factory IptvPlaylist.fromJson(Map<String, dynamic> json) => IptvPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    content: json['content'] as String?,
    serverUrl: json['serverUrl'] as String?,
    username: json['username'] as String?,
    password: json['password'] as String?,
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
  final String? contentType; // 'live', 'vod', or null (M3U channels)
  final Map<String, String> attributes; // Additional tvg-* attributes

  const IptvChannel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.group,
    this.duration,
    this.contentType,
    this.attributes = const {},
  });

  /// Check if this is a live stream (no duration or -1 duration)
  bool get isLive => duration == null || duration == -1;

  /// Get tvg-id attribute if present
  String? get tvgId => attributes['tvg-id'];

  /// Get tvg-name attribute if present
  String? get tvgName => attributes['tvg-name'];

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    if (logoUrl != null) 'logoUrl': logoUrl,
    if (group != null) 'group': group,
    if (duration != null) 'duration': duration,
    if (contentType != null) 'contentType': contentType,
  };

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
