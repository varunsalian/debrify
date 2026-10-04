/// The edited values a [_EditPlaylistDialog] returns. Only the fields relevant
/// to the playlist's type are populated; the caller rebuilds the playlist.
class IptvSettingsPlaylistEdit {
  const IptvSettingsPlaylistEdit({
    required this.name,
    required this.url,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.epgUrl,
  });

  final String name;
  final String url; // M3U URL playlists only
  final String? serverUrl; // Xtream only
  final String? username; // Xtream only
  final String? password; // Xtream only
  final String? epgUrl;
}
