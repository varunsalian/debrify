import 'dart:async' show unawaited;

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'iptv_settings_input_owner.dart';
import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsUrlAddDeps = ({
  Future<void> Function(Future<void> Function() body) runProfileAction,
  IptvSettingsInputOwner inputOwner,
  void Function(String message, {bool isError}) showSnackBar,
  IptvSettingsSourcesOwner sourcesOwner,
  void Function(VoidCallback) setState,
  bool Function() mounted,
  void Function() ensureFocusNodes,
});

class IptvSettingsUrlAdd {
  IptvSettingsUrlAdd(this._deps);
  final IptvSettingsUrlAddDeps _deps;

  Future<void> addPlaylist() => _deps.runProfileAction(addPlaylistForProfile);

  Future<void> addPlaylistForProfile() async {
    // The busy button is a no-op, but the fields' onSubmitted calls this
    // directly — guard so an in-flight add can't run twice.
    if (_deps.inputOwner.isAdding) return;
    final name = _deps.inputOwner.nameController.text.trim();
    final url = _deps.inputOwner.urlController.text.trim();

    if (name.isEmpty) {
      _deps.showSnackBar('Please enter a playlist name');
      return;
    }

    if (url.isEmpty) {
      _deps.showSnackBar('Please enter a playlist URL');
      return;
    }

    if (!IptvService.isValidPlaylistUrl(url)) {
      _deps.showSnackBar('Please enter a valid HTTP/HTTPS URL');
      return;
    }

    // Check for duplicate URL
    if (_deps.sourcesOwner.playlists.any((p) => p.url == url)) {
      _deps.showSnackBar('This playlist URL already exists');
      return;
    }

    _deps.setState(() => _deps.inputOwner.isAdding = true);

    // Validate URL by trying to fetch it
    final playlistId = DateTime.now().microsecondsSinceEpoch.toString();
    final result = await IptvService.instance.fetchPlaylist(
      url,
      numberingSourceKey: playlistId,
      allowUnbound: true,
    );

    if (!_deps.mounted()) return;

    if (result.hasError) {
      _deps.setState(() => _deps.inputOwner.isAdding = false);
      _deps.showSnackBar('Failed to load playlist: ${result.error}');
      return;
    }

    if (result.isEmpty) {
      _deps.setState(() => _deps.inputOwner.isAdding = false);
      _deps.showSnackBar('Playlist is empty or invalid');
      return;
    }

    // Create new playlist
    final epgUrl = _deps.inputOwner.epgUrlController.text.trim();
    final playlist = IptvPlaylist(
      id: playlistId,
      name: name,
      url: url,
      epgUrl: epgUrl.isEmpty ? null : epgUrl,
      addedAt: DateTime.now(),
    );

    final newPlaylists = [..._deps.sourcesOwner.playlists, playlist];
    final savedPlaylists = await IptvPlaylistStorage.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
    );
    if (!_deps.mounted()) return;

    _deps.setState(() {
      _deps.sourcesOwner.playlists = savedPlaylists;
      _deps.inputOwner.nameController.clear();
      _deps.inputOwner.urlController.clear();
      _deps.inputOwner.epgUrlController.clear();
      _deps.inputOwner.isAdding = false;
    });
    _deps.ensureFocusNodes();

    unawaited(IptvCatalogRefreshService.instance.refreshDue());

    _deps.showSnackBar(
      // DB-catalog mode returns an ingest receipt with empty channels — the
      // count lives on the receipt.
      'Added "$name" '
      '(${result.ingest?.channelCount ?? result.channels.length} channels)',
      isError: false,
    );
  }
}
