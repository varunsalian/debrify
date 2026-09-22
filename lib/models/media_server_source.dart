import 'dart:convert';

/// Secret-free identity shared by playback, pin dedupe, sync and restoration.
class MediaServerSource {
  const MediaServerSource({
    required this.serverId,
    required this.contentId,
    required this.isMovie,
    required this.variant,
  });

  final String serverId;
  final String contentId;
  final bool isMovie;
  final String variant;

  static MediaServerSource? tryDecode(String value) {
    try {
      final data = jsonDecode(value);
      if (data is! Map || data['isMovie'] is! bool) return null;
      for (final key in ['serverId', 'contentId', 'variant']) {
        if (data[key] is! String || (data[key] as String).isEmpty) return null;
      }
      return MediaServerSource(
        serverId: data['serverId'] as String,
        contentId: data['contentId'] as String,
        isMovie: data['isMovie'] as bool,
        variant: data['variant'] as String,
      );
    } on FormatException {
      return null;
    }
  }

  // Alphabetical keys also agree with WebDAV's canonical JSON encoding.
  String encode() => jsonEncode({
    'contentId': contentId,
    'isMovie': isMovie,
    'serverId': serverId,
    'variant': variant,
  });

  MediaServerSource remap(Map<String, String> resources) => MediaServerSource(
    serverId: resources[serverId] ?? serverId,
    contentId: contentId,
    isMovie: isMovie,
    variant: variant,
  );

  static String bindingKey(String encoded) =>
      'media-server:${tryDecode(encoded)?.encode() ?? encoded}';

  /// Quick Play lowercases provider keys, unlike case-sensitive resource IDs.
  /// Normalize only these keys, never pin descriptors or other resource data.
  static String remapPriorityKey(String value, Map<String, String> resources) {
    const prefix = 'mediaserver:';
    if (!value.startsWith(prefix)) return value;
    final id = value.substring(prefix.length);
    final normalizedId = id.toLowerCase();
    var replacement = resources[id] ?? resources[normalizedId];
    if (replacement == null) {
      for (final entry in resources.entries) {
        if (entry.key.toLowerCase() == normalizedId) {
          replacement = entry.value;
          break;
        }
      }
    }
    return replacement == null ? value : '$prefix${replacement.toLowerCase()}';
  }
}
