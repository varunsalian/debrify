import 'dart:async' show unawaited;

import 'package:debrify/features/iptv_settings/application/normalize_xtream_server_url.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'iptv_settings_input_owner.dart';
import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsXtreamAddDeps = ({
  Future<void> Function(Future<void> Function() body) runProfileAction,
  IptvSettingsInputOwner inputOwner,
  void Function(String message, {bool isError}) showSnackBar,
  IptvSettingsSourcesOwner sourcesOwner,
  void Function(VoidCallback) setState,
  bool Function() mounted,
  void Function() ensureFocusNodes,
});

class IptvSettingsXtreamAdd {
  IptvSettingsXtreamAdd(this._deps);
  final IptvSettingsXtreamAddDeps _deps;

  Future<void> addXtreamCodes() =>
      _deps.runProfileAction(addXtreamCodesForProfile);

  Future<void> addXtreamCodesForProfile() async {
    // Same double-submission guard as _addPlaylist (fields' onSubmitted).
    if (_deps.inputOwner.isXcAdding) return;
    final server = _deps.inputOwner.xcServerController.text.trim();
    final username = _deps.inputOwner.xcUsernameController.text.trim();
    final password = _deps.inputOwner.xcPasswordController.text.trim();

    if (server.isEmpty) {
      _deps.showSnackBar('Please enter a server URL');
      return;
    }
    if (username.isEmpty) {
      _deps.showSnackBar('Please enter a username');
      return;
    }
    if (password.isEmpty) {
      _deps.showSnackBar('Please enter a password');
      return;
    }

    final serverUrl = normalizeXtreamServerUrl(server);
    if (serverUrl == null) {
      _deps.showSnackBar('Please enter a valid server URL');
      return;
    }

    // Check for duplicate
    if (_deps.sourcesOwner.playlists.any(
      (p) =>
          p.isXtreamCodes && p.serverUrl == serverUrl && p.username == username,
    )) {
      _deps.showSnackBar('This Xtream Codes login already exists');
      return;
    }

    _deps.setState(() => _deps.inputOwner.isXcAdding = true);

    final result = await XtreamCodesService.instance.authenticate(
      serverUrl,
      username,
      password,
    );

    if (!_deps.mounted()) return;

    if (!result.success) {
      _deps.setState(() => _deps.inputOwner.isXcAdding = false);
      _deps.showSnackBar(result.error ?? 'Authentication failed');
      return;
    }

    // Create playlist with XC fields. Honor a user-supplied name; fall back to
    // the username@host label when the optional name field is left blank.
    final customName = _deps.inputOwner.xcNameController.text.trim();
    final playlist = IptvPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: customName.isEmpty
          ? '$username@${Uri.parse(serverUrl).host}'
          : customName,
      url: '',
      serverUrl: serverUrl,
      username: username,
      password: password,
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
      _deps.inputOwner.xcNameController.clear();
      _deps.inputOwner.xcServerController.clear();
      _deps.inputOwner.xcUsernameController.clear();
      _deps.inputOwner.xcPasswordController.clear();
      _deps.inputOwner.isXcAdding = false;
    });
    _deps.ensureFocusNodes();
    unawaited(IptvCatalogRefreshService.instance.refreshDue());

    // Build status message
    String statusMsg = 'Added Xtream Codes login';
    if (result.status != null) statusMsg += ' (${result.status}';
    if (result.expDate != null) {
      statusMsg +=
          ', expires ${result.expDate!.year}-${result.expDate!.month.toString().padLeft(2, '0')}-${result.expDate!.day.toString().padLeft(2, '0')}';
    }
    if (result.status != null) statusMsg += ')';
    _deps.showSnackBar(statusMsg, isError: false);
  }
}
