// Composition for Settings › Search sources: binds the page to the profile's
// stored choices and its searchable IPTV playlists.
import 'package:debrify/features/source_search_settings/presentation/source_search_settings_page.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/source_search_preferences.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:flutter/material.dart';

Future<void> openSourceSearchSettings(BuildContext context) => pushSettingsPage(
  context,
  SourceSearchSettingsPage(
    loadPlaylists: _searchablePlaylists,
    read: SourceSearchPreferences.read,
    write: SourceSearchPreferences.write,
    owner: () => ProfileRuntime.scope.value,
  ),
);

/// The playlists title search can query (the same test IptvSourceSearch
/// applies): no toggles for playlists search never reaches.
Future<List<SourceSearchPlaylist>> _searchablePlaylists() async {
  final playlists = await IptvPlaylistStorage.getIptvPlaylists(
    forSettings: false,
  );
  return [
    for (final p in playlists)
      if (_searchable(p)) (id: p.id, name: p.name),
  ];
}

bool _searchable(IptvPlaylist p) =>
    !p.credentialsRedacted &&
    !p.isVirtual &&
    !p.isLocalFile &&
    (p.isXtreamCodes || p.url.isNotEmpty);
