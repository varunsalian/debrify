enum MediaServerKind {
  jellyfin('Jellyfin'),
  emby('Emby');

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
  });

  final MediaServerKind kind;
  final String baseUrl;
  final String userId;
  final String token;
  final String serverId;
  final String deviceId;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'baseUrl': baseUrl,
    'userId': userId,
    'token': token,
    'serverId': serverId,
    'deviceId': deviceId,
  };

  factory MediaServerAccount.fromJson(Map<String, dynamic> value) =>
      MediaServerAccount(
        kind: MediaServerKind.values.byName(value['kind'] as String),
        baseUrl: value['baseUrl'] as String,
        userId: value['userId'] as String,
        token: value['token'] as String,
        serverId: value['serverId'] as String,
        deviceId: value['deviceId'] as String,
      );
}

class MediaServerException implements Exception {
  const MediaServerException(this.message);
  final String message;
  @override
  String toString() => message;
}
