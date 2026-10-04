import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;

class IptvSettingsSourcesOwner {
  /// Hidden-category counts per playlist id, for the section's row subtitles.
  /// Read from the catalog DB on load rather than per build — a settings
  /// rebuild must not query once per source.
  Map<String, int> hiddenCounts = const {};

  List<IptvListMeta> lists = [];

  List<IptvPlaylist> playlists = [];
  String? defaultPlaylistId;

  bool loading = true;
  // Ids of playlists currently being refreshed (re-fetched from source)
  final Set<String> refreshingIds = {};
}
