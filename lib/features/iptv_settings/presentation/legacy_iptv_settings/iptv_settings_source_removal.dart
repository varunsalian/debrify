import 'package:debrify/features/iptv_settings/presentation/iptv_shared_source_delete_dialog.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

import 'iptv_settings_focus_owner.dart';
import 'iptv_settings_input_owner.dart';
import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsSourceRemovalDeps = ({
  bool Function() mounted,
  void Function(String message, {bool isError}) showSnackBar,
  BuildContext Function() context,
  IptvSettingsSourcesOwner sourcesOwner,
  Map<String, WebDavSyncCatalogOwnerReference> Function(IptvPlaylist playlist)
  catalogOwnerReferencesFor,
  List<String> Function(IptvPlaylist playlist) catalogKeysFor,
  void Function(VoidCallback) setState,
  void Function() ensureFocusNodes,
  IptvSettingsFocusOwner focusOwner,
  void Function(FocusNode node) focusAndReveal,
  IptvSettingsInputOwner inputOwner,
});

class IptvSettingsSourceRemoval {
  IptvSettingsSourceRemoval(this._deps);
  final IptvSettingsSourceRemovalDeps _deps;

  Future<void> removePlaylist(IptvPlaylist playlist) async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
      );
      if (!_deps.mounted()) return;
      if (authorization == null) {
        await removePlaylistForProfile(playlist);
      } else {
        await authorization.runIfCurrent(
          () => removePlaylistForProfile(
            playlist,
            initiatingAuthorization: authorization,
          ),
        );
      }
    } catch (_) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar(
        'Could not remove "${playlist.name}". Please try again.',
        isError: true,
      );
    }
  }

  Future<void> removePlaylistForProfile(
    IptvPlaylist playlist, {
    ProfileAsyncAuthorization? initiatingAuthorization,
  }) async {
    var revokeBorrowers = false;
    final resourceId = playlist.connectionResourceId;
    if (ProfileCollectionResourceFacade.active && resourceId != null) {
      final borrowerCount =
          await ProfileCollectionResourceFacade.ownedBorrowerCount(
            resourceId: resourceId,
            feature: ProfileFeature.manageConnections,
          );
      if (borrowerCount > 0) {
        final registry = ProfileBootstrap.registry;
        var authorization = await ProfileAuthorizationContext.capture(registry);
        var actor = await authorization.validate(registry);
        if (!actor.isAdmin || !actor.allows(ProfileFeature.manageProfiles)) {
          if (_deps.mounted()) {
            _deps.showSnackBar(
              'Only an Admin can remove a source shared with other profiles.',
              isError: true,
            );
          }
          return;
        }
        if (!_deps.mounted()) return;
        final confirmed = await showDialog<bool>(
          context: _deps.context(),
          builder: (_) => IptvSharedSourceDeleteDialog(
            playlistName: playlist.name,
            borrowerCount: borrowerCount,
          ),
        );
        if (confirmed != true || !_deps.mounted()) return;
        try {
          await initiatingAuthorization?.runIfCurrent(() async {});
        } on StateError {
          _deps.showSnackBar(
            'The active profile changed. Nothing was removed.',
            isError: true,
          );
          return;
        }

        // The dialog is an async authorization boundary. Capture and verify
        // the visible actor again so an Admin confirmation cannot be replayed
        // after a profile switch, lock, or role/policy change.
        authorization = await ProfileAuthorizationContext.capture(registry);
        actor = await authorization.validate(registry);
        if (!actor.isAdmin || !actor.allows(ProfileFeature.manageProfiles)) {
          _deps.showSnackBar(
            'Admin authorization changed. Nothing was removed.',
            isError: true,
          );
          return;
        }
        revokeBorrowers = true;
      }
    }

    final removedIndex = _deps.sourcesOwner.playlists.indexWhere(
      (p) => p.id == playlist.id,
    );
    final newPlaylists = _deps.sourcesOwner.playlists
        .where((p) => p.id != playlist.id)
        .toList();
    final savedPlaylists = await IptvPlaylistStorage.setIptvPlaylistsAndReload(
      newPlaylists,
      forSettings: true,
      revokeBorrowers: revokeBorrowers,
    );
    await IptvCatalogDb.archiveNumberingSource(playlist.id);

    // If removed playlist was the default, clear default
    if (_deps.sourcesOwner.defaultPlaylistId == playlist.id) {
      await IptvPlaylistStorage.setIptvDefaultPlaylist(null);
      _deps.sourcesOwner.defaultPlaylistId = null;
    }

    // Clear caches for this playlist — the in-memory fetch cache and the
    // catalog DB rows.
    if (playlist.isXtreamCodes) {
      XtreamCodesService.instance.clearCache(playlist.serverUrl);
      await IptvCatalogDb.removeCatalogsByKeys(
        IptvCatalogKey.allForXtream(
          playlist.serverUrl!,
          playlist.username ?? '',
        ),
        forgetChannelOrders: true,
        ownerReferences: _deps.catalogOwnerReferencesFor(playlist),
      );
    } else if (!playlist.isLocalFile && playlist.url.isNotEmpty) {
      IptvService.instance.clearCache(playlist.url);
      await IptvCatalogDb.removeCatalogsByKeys(
        [IptvCatalogKey.forUrl(playlist.url)],
        forgetChannelOrders: true,
        ownerReferences: _deps.catalogOwnerReferencesFor(playlist),
      );
    }
    // The source's hidden categories go with it. Deliberately here and not
    // inside the catalog delete: a manual REFRESH also drops and re-ingests
    // the catalog under the same keys, and user rules must survive that.
    IptvCatalogDb.forgetHiddenGroups(
      _deps.catalogKeysFor(playlist),
      origin: WebDavSyncMutationOrigin.user,
      ownerReferences: _deps.catalogOwnerReferencesFor(playlist),
    );
    if (playlist.isLocalFile) {
      try {
        await IptvCatalogDb.forgetCategoryOrders([
          IptvCatalogKey.forLocalCategoryOrder(playlist.id),
        ], ownerReferences: _deps.catalogOwnerReferencesFor(playlist));
      } catch (error) {
        // Category order is optional catalog metadata. Failure to open a
        // damaged cache must not prevent the source itself being removed.
        debugPrint(
          'IPTV settings: local category-order cleanup skipped ($error)',
        );
      }
    }
    await IptvFavoritesStorage.removeIptvCategoryOrdersForSource(playlist.id);

    // Remove list memberships and watch history that belonged to this
    // playlist — both replay from stored metadata, so either would otherwise
    // keep offering streams that no longer authenticate. The sweep covers
    // EVERY list, not just Favorites: the provider is gone, so its channels
    // have nowhere left to play from. The lists themselves survive, possibly
    // empty.
    await IptvFavoritesStorage.removeIptvListChannelsByPlaylistId(playlist.id);
    await IptvHistoryStorage.removeIptvWatchHistoryByPlaylistId(playlist.id);

    if (!_deps.mounted()) return;
    _deps.setState(() => _deps.sourcesOwner.playlists = savedPlaylists);
    // _ensureFocusNodes disposes the trailing nodes — including the one the
    // focused delete button was using — so reseed DPAD focus on the same row
    // slot of a surviving playlist (or the tab bar when the list empties).
    _deps.ensureFocusNodes();
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        if (_deps.focusOwner.playlistFocusNodes.isEmpty) {
          _deps.focusAndReveal(switch (_deps.inputOwner.tabController.index) {
            1 => _deps.focusOwner.fileTabFocusNode,
            2 => _deps.focusOwner.xcTabFocusNode,
            _ => _deps.focusOwner.urlTabFocusNode,
          });
        } else {
          final row = removedIndex.clamp(
            0,
            _deps.sourcesOwner.playlists.length - 1,
          );
          _deps.focusAndReveal(_deps.focusOwner.playlistFocusNodes[row * 4]);
        }
      });
    }
    _deps.showSnackBar('Removed "${playlist.name}"', isError: false);
  }
}
