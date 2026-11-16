enum MediaServerKind {
  jellyfin('Jellyfin'),
  emby('Emby'),
  plex('Plex');

  const MediaServerKind(this.label);
  final String label;
}

/// Credentials are held in the encrypted connection registry, never preferences.
class MediaServerAccount {
  const MediaServerAccount({
    required this.kind,
    required this.baseUrl,
    required this.userId,
    required this.token,
    required this.serverId,
    required this.deviceId,
    this.connections = const [],
  });

  final MediaServerKind kind;
  final String baseUrl;
  final String userId;
  final String token;
  final String serverId;
  final String deviceId;

  /// Plex only: the addresses this connection may use, in priority order.
  /// Only addresses allowed at sign-in are stored, so whatever is listed
  /// may be used. Empty for Jellyfin/Emby, whose JSON is unchanged.
  final List<MediaServerConnection> connections;

  /// Whether [baseUrl] is a Plex relay, which Plex limits in speed.
  bool get usesRelay => connections.any((c) => c.relay && c.uri == baseUrl);

  MediaServerAccount withBaseUrl(String value) => MediaServerAccount(
    kind: kind,
    baseUrl: value,
    userId: userId,
    token: token,
    serverId: serverId,
    deviceId: deviceId,
    connections: connections,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'baseUrl': baseUrl,
    'userId': userId,
    'token': token,
    'serverId': serverId,
    'deviceId': deviceId,
    if (connections.isNotEmpty)
      'connections': [for (final c in connections) c.toJson()],
  };

  factory MediaServerAccount.fromJson(Map<String, dynamic> value) =>
      MediaServerAccount(
        kind: MediaServerKind.values.byName(value['kind'] as String),
        baseUrl: value['baseUrl'] as String,
        userId: value['userId'] as String,
        token: value['token'] as String,
        serverId: value['serverId'] as String,
        deviceId: value['deviceId'] as String,
        connections: [
          for (final c in value['connections'] as List? ?? const [])
            MediaServerConnection.fromJson((c as Map).cast<String, dynamic>()),
        ],
      );
}

/// One stored Plex address. Never contains credentials.
class MediaServerConnection {
  const MediaServerConnection({required this.uri, this.relay = false});

  final String uri;
  final bool relay;

  Map<String, dynamic> toJson() => {'uri': uri, if (relay) 'relay': true};

  factory MediaServerConnection.fromJson(Map<String, dynamic> value) =>
      MediaServerConnection(
        uri: value['uri'] as String,
        relay: value['relay'] == true,
      );
}

class MediaServerException implements Exception {
  const MediaServerException(this.message);
  final String message;
  @override
  String toString() => message;
}
