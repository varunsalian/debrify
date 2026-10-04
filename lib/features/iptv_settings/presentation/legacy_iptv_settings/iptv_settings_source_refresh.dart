import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsSourceRefreshDeps = ({
  Future<void> Function(Future<void> Function() body) runProfileAction,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  IptvSettingsSourcesOwner sourcesOwner,
  void Function(String message, {bool isError}) showSnackBar,
});

class IptvSettingsSourceRefresh {
  IptvSettingsSourceRefresh(this._deps);
  final IptvSettingsSourceRefreshDeps _deps;

  Future<void> setDefaultPlaylist(IptvPlaylist? playlist) =>
      _deps.runProfileAction(() => setDefaultPlaylistForProfile(playlist));

  Future<void> setDefaultPlaylistForProfile(IptvPlaylist? playlist) async {
    await IptvPlaylistStorage.setIptvDefaultPlaylist(playlist?.id);
    if (!_deps.mounted()) return;
    _deps.setState(() => _deps.sourcesOwner.defaultPlaylistId = playlist?.id);
    _deps.showSnackBar(
      playlist != null
          ? 'Default set to "${playlist.name}"'
          : 'Default cleared',
      isError: false,
    );
  }

  /// Re-fetch a URL or Xtream Codes playlist from its source. Local files are
  /// static snapshots and cannot be refreshed.
  Future<void> refreshPlaylist(IptvPlaylist playlist) =>
      _deps.runProfileAction(() => refreshPlaylistForProfile(playlist));

  Future<void> refreshPlaylistForProfile(IptvPlaylist playlist) async {
    if (playlist.isLocalFile || playlist.connectionReadOnly) return;
    if (_deps.sourcesOwner.refreshingIds.contains(playlist.id)) return;
    final startingScope = ProfileRuntime.scope.value;
    bool isCurrent() => ProfileRuntime.scope.value == startingScope;

    _deps.setState(() => _deps.sourcesOwner.refreshingIds.add(playlist.id));
    _deps.showSnackBar('Refreshing "${playlist.name}"…', isError: false);

    IptvParseResult result = IptvParseResult(channels: [], categories: []);
    final refreshedSections = <String>[];
    final failedSections = <String>[];
    // Keep the previous snapshot until its replacement succeeds. Fetch in
    // sequence for low-memory TVs; a failed section must not skip the others.
    final sections = playlist.isXtreamCodes
        ? [('live', 'live channels'), ('vod', 'movies'), ('series', 'series')]
        : [('live', 'channels')];
    for (final section in sections) {
      if (!isCurrent()) break;
      try {
        result = await IptvCatalogRefreshService.instance.refreshCatalog(
          playlist,
          section.$1,
          force: true,
          priority: true,
        );
      } catch (e) {
        result = IptvParseResult(channels: [], categories: [], error: '$e');
      }
      if (result.hasError) {
        failedSections.add(section.$2);
      } else {
        final count = result.ingest?.channelCount ?? result.channels.length;
        refreshedSections.add('$count ${section.$2}');
      }
    }

    if (!_deps.mounted()) return;
    _deps.setState(() => _deps.sourcesOwner.refreshingIds.remove(playlist.id));
    if (!isCurrent()) return;

    if (playlist.isXtreamCodes &&
        (refreshedSections.isNotEmpty || failedSections.isNotEmpty)) {
      final updated = refreshedSections.isEmpty
          ? ''
          : 'Updated ${refreshedSections.join(', ')}. ';
      final failed = failedSections.isEmpty
          ? ''
          : 'Failed to refresh ${failedSections.join(', ')}; try again.';
      _deps.showSnackBar(
        '"${playlist.name}" — $updated$failed',
        isError: failedSections.isNotEmpty,
      );
    } else if (result.hasError) {
      _deps.showSnackBar(
        'Failed to refresh "${playlist.name}": ${result.error}',
      );
    } else {
      final suffix = result.warning != null ? ' (${result.warning})' : '';
      final count = result.ingest?.channelCount ?? result.channels.length;
      _deps.showSnackBar(
        'Updated "${playlist.name}" — $count channels$suffix',
        isError: false,
      );
    }
  }
}
