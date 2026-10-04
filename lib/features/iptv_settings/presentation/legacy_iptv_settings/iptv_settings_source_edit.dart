import 'package:debrify/features/iptv_settings/application/normalize_xtream_server_url.dart';
import 'package:debrify/features/iptv_settings/models/iptv_settings_playlist_edit.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:flutter/material.dart';

import 'iptv_settings_edit_dialog.dart';
import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsSourceEditDeps = ({
  Future<void> Function(Future<void> Function() body) runProfileAction,
  BuildContext Function() context,
  IptvSettingsSourcesOwner sourcesOwner,
  bool Function() mounted,
  void Function(String message, {bool isError}) showSnackBar,
  List<String> Function(IptvPlaylist playlist) catalogKeysFor,
  Map<String, WebDavSyncCatalogOwnerReference> Function(IptvPlaylist playlist)
  catalogOwnerReferencesFor,
  void Function(VoidCallback) setState,
});

class IptvSettingsSourceEdit {
  IptvSettingsSourceEdit(this._deps);
  final IptvSettingsSourceEditDeps _deps;

  /// Edit an existing playlist in place: rename it, change its guide (EPG) URL,
  /// and — depending on type — its source URL (M3U URL playlists) or its
  /// server/username/password (Xtream logins). The id and added-at are
  /// preserved so favorites and watch history stay attached. When the source
  /// actually changes, the stale fetch cache is cleared so the next load picks
  /// up the new source; the user can Refresh to re-verify.
  Future<void> editPlaylist(IptvPlaylist playlist) =>
      _deps.runProfileAction(() => editPlaylistForProfile(playlist));

  Future<void> editPlaylistForProfile(IptvPlaylist playlist) async {
    final result = await showDialog<IptvSettingsPlaylistEdit>(
      context: _deps.context(),
      builder: (context) => Theme(
        data: settingsPageTheme(context),
        child: IptvSettingsEditDialog(
          playlist: playlist,
          // Exclude this playlist from the duplicate checks — keeping its own
          // name/URL must not read as a collision.
          existingNames: _deps.sourcesOwner.playlists
              .where((p) => p.id != playlist.id)
              .map((p) => p.name)
              .toSet(),
          existingUrls: _deps.sourcesOwner.playlists
              .where(
                (p) =>
                    p.id != playlist.id && !p.isXtreamCodes && !p.isLocalFile,
              )
              .map((p) => p.url)
              .toSet(),
        ),
      ),
    );
    if (result == null || !_deps.mounted()) {
      return;
    } // cancelled or profile switched

    // Normalize an edited Xtream server URL the same way add does.
    String? newServerUrl = playlist.serverUrl;
    if (playlist.isXtreamCodes) {
      newServerUrl = normalizeXtreamServerUrl(result.serverUrl ?? '');
      if (newServerUrl == null) {
        _deps.showSnackBar('Please enter a valid server URL');
        return;
      }
    }

    final epg = (result.epgUrl ?? '').trim();
    final updated = IptvPlaylist(
      id: playlist.id,
      name: result.name,
      // URL playlists take the edited URL; Xtream/local keep their existing
      // url field (empty / snapshot-bound respectively).
      url: playlist.isXtreamCodes || playlist.isLocalFile
          ? playlist.url
          : result.url,
      content: playlist.content,
      serverUrl: playlist.isXtreamCodes ? newServerUrl : playlist.serverUrl,
      username: playlist.isXtreamCodes ? result.username : playlist.username,
      password: playlist.isXtreamCodes ? result.password : playlist.password,
      epgUrl: epg.isEmpty ? null : epg,
      addedAt: playlist.addedAt,
      connectionResourceId: playlist.connectionResourceId,
      connectionResourceRevision: playlist.connectionResourceRevision,
      connectionReadOnly: playlist.connectionReadOnly,
      // The validated editor result supplies the replacement source details.
      // Keeping the placeholder flag would silently retain the old secret.
      credentialsRedacted: false,
    );

    final unreachableKeys = _deps
        .catalogKeysFor(playlist)
        .toSet()
        .difference(_deps.catalogKeysFor(updated).toSet());

    // Drop the stale caches when the source changed so the next load doesn't
    // serve the old channels — the in-memory fetch cache and the on-disk
    // catalog snapshots (the new source's snapshots rebuild on next load).
    if (playlist.isXtreamCodes) {
      final credsChanged =
          playlist.serverUrl != updated.serverUrl ||
          playlist.username != updated.username ||
          playlist.password != updated.password;
      if (credsChanged) {
        XtreamCodesService.instance.clearCache(playlist.serverUrl);
        XtreamCodesService.instance.clearCache(updated.serverUrl);
        await IptvCatalogDb.removeCatalogsByKeys(
          IptvCatalogKey.allForXtream(
            playlist.serverUrl!,
            playlist.username ?? '',
          ),
          forgetChannelOrders: unreachableKeys.isNotEmpty,
          ownerReferences: _deps.catalogOwnerReferencesFor(playlist),
        );
      }
    } else if (!playlist.isLocalFile && playlist.url != updated.url) {
      IptvService.instance.clearCache(playlist.url);
      await IptvCatalogDb.removeCatalogsByKeys(
        [IptvCatalogKey.forUrl(playlist.url)],
        forgetChannelOrders: true,
        ownerReferences: _deps.catalogOwnerReferencesFor(playlist),
      );
    }

    // Hidden-category rules follow the source's IDENTITY, not its catalogs:
    // clear only the keys this edit makes unreachable, or they sit orphaned
    // and silently reattach if that endpoint/account is ever added again.
    //
    // Set difference rather than "did anything change": a PASSWORD-only edit
    // deletes and re-ingests the catalogs above, but the key is
    // server+username+type, so its keys are unchanged and its rules must
    // survive. Same for a rename.
    IptvCatalogDb.forgetHiddenGroups(
      unreachableKeys,
      origin: WebDavSyncMutationOrigin.user,
      ownerReferences: _deps.catalogOwnerReferencesFor(playlist),
    );

    final newPlaylists = [
      for (final p in _deps.sourcesOwner.playlists)
        if (p.id == playlist.id) updated else p,
    ];
    final savedPlaylists = await IptvPlaylistStorage.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
    );
    if (!_deps.mounted()) return;
    _deps.setState(() => _deps.sourcesOwner.playlists = savedPlaylists);
    _deps.showSnackBar('Updated "${updated.name}"', isError: false);
  }
}
