import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/widgets/iptv/iptv_list_name_dialog.dart';
import 'package:debrify/widgets/iptv/iptv_list_picker_dialog.dart';
import 'package:flutter/material.dart';

typedef IptvFavoritesDeps = ({
  IptvCatalogState catalogState,
  IptvMembershipState membershipState,
  IptvSettingsState settingsState,
  BuildContext Function() context,
  Future<void> Function(IptvPlaylist playlist, {bool userRequested})
  loadPlaylist,
  bool Function() mounted,

  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  // TEMP(iptv): _refreshListShelfPresence -> IptvPlaybackRefresh.refreshListShelfPresence (step 5).
  void Function() refreshListShelfPresence,
  StateSetter setState,
});

class IptvFavorites {
  final IptvFavoritesDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvMembershipState _membershipState;
  final IptvSettingsState _settingsState;

  IptvFavorites(this._deps)
    : _catalogState = _deps.catalogState,
      _membershipState = _deps.membershipState,
      _settingsState = _deps.settingsState;

  /// The user's own lists — empty until they create one, which is what keeps
  /// hold-OK meaning "toggle favorite" for everyone who never does.
  List<IptvListMeta> get customLists => [
    for (final list in _membershipState.lists)
      if (!list.isBuiltin) list,
  ];

  /// Virtual playlist for a user-created list. Ids are derived from the list
  /// id so the player payload, the picker and the browse round-trip all agree
  /// on one identity.
  static IptvPlaylist listPlaylist(IptvListMeta list) => IptvPlaylist(
    id: 'iptv-list-${list.id}',
    name: list.name,
    url: 'list://${list.id}',
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Future<void> loadFavorites() async {
    final lists = await IptvFavoritesStorage.getIptvLists();
    final snapshot = await IptvFavoritesStorage.getIptvMembershipSnapshot();
    if (_deps.mounted()) {
      _deps.setState(() {
        _membershipState.lists = lists;
        _membershipState.membership = snapshot.membership;
        _membershipState.favoriteUrls = {
          for (final entry in snapshot.membership.entries)
            if (entry.value.contains(IptvFavoritesStorage.iptvFavoritesListId))
              entry.key,
        };
        _membershipState.favoritePlaylistIds = snapshot.origins;
      });
    }
  }

  /// The real playlist a channel belongs to. Inside a virtual shelf the
  /// selected playlist is not a provider at all, so writing its id into the
  /// favorites/history stores would break the sweep that runs when a provider
  /// is deleted (nothing would match 'iptv-favorites' or 'iptv-continue') and
  /// strand entries pointing at URLs that no longer authenticate.
  String? originPlaylistIdFor(IptvChannel channel) {
    final playlist = _settingsState.selectedPlaylist;
    if ((playlist?.isFavorites ?? false) || (playlist?.isCustomList ?? false)) {
      // The shelf's own rows carry the origin of the exact membership they
      // were rebuilt from — the only source that stays correct when the same
      // URL sits in two lists under two providers.
      final rowOrigin =
          channel.attributes[IptvMembershipState.kListOriginAttribute];
      if (rowOrigin != null && rowOrigin.isNotEmpty) return rowOrigin;
      final listId = playlist!.isFavorites
          ? IptvFavoritesStorage.iptvFavoritesListId
          : playlist.customListId;
      if (listId == null) return null;
      return _membershipState.favoritePlaylistIds[(listId, channel.url)];
    }
    if (playlist?.isContinueWatching ?? false) {
      return _membershipState.continuePlaylistIds[channel.url];
    }
    return playlist?.id;
  }

  Future<void> toggleFavorite(IptvChannel channel, bool isFavorited) async {
    await IptvFavoritesStorage.setIptvChannelFavorited(
      channel.url,
      isFavorited,
      channelName: channel.name,
      logoUrl: channel.logoUrl,
      group: channel.group,
      playlistId: originPlaylistIdFor(channel),
      channelNumber: channel.channelNumber,
      // A list is replayed from stored metadata, never re-parsed from the
      // playlist — so the channel's own headers have to travel with it, and
      // so does what it IS: without a content type a movie comes back as a
      // live channel and loses its resume bar.
      contentType: channel.contentType,
      duration: channel.duration,
      httpHeaders: channel.httpHeaders,
    );
    if (_deps.mounted()) {
      _deps.setState(() {
        if (isFavorited) {
          _membershipState.favoriteUrls.add(channel.url);
          _membershipState.membership = {
            ..._membershipState.membership,
            channel.url: {
              ...?_membershipState.membership[channel.url],
              IptvFavoritesStorage.iptvFavoritesListId,
            },
          };
        } else {
          _membershipState.favoriteUrls.remove(channel.url);
          _membershipState.membership = {
            ..._membershipState.membership,
            channel.url: {...?_membershipState.membership[channel.url]}
              ..remove(IptvFavoritesStorage.iptvFavoritesListId),
          };
        }
      });
    }
    // Deliberately no shelf reload here, even inside the Favorites view: a
    // reload disposes every row's focus node (see _loadPlaylist) and would
    // scramble DPAD focus out from under the hold the user just finished.
    // The row stays with an empty heart until the next natural reload —
    // which is what it has always done.
  }

  /// Open the "add to list" picker for [channel]. Only reachable once the
  /// user has created a list — before that, the same gesture toggles the
  /// favorite outright, so nobody grows an extra tap they didn't ask for.
  Future<void> openListPicker(IptvChannel channel) async {
    final changed = await showIptvListPickerDialog(
      context: _deps.context(),
      channelName: channel.name,
      channelLogoUrl: channel.logoUrl,
      loadLists: () => IptvFavoritesStorage.getIptvLists(),
      loadMembership: () =>
          IptvFavoritesStorage.getIptvListsForChannel(channel.url),
      onSetMembership: (listId, inList) =>
          IptvFavoritesStorage.setIptvChannelInList(
            listId,
            channel.url,
            inList,
            channelName: channel.name,
            logoUrl: channel.logoUrl,
            group: channel.group,
            playlistId: originPlaylistIdFor(channel),
            channelNumber: channel.channelNumber,
            contentType: channel.contentType,
            duration: channel.duration,
            httpHeaders: channel.httpHeaders,
          ),
      onCreateList: (name) => IptvFavoritesStorage.createIptvList(name),
    );
    if (!changed || !_deps.mounted()) return;
    await loadFavorites();
    if (!_deps.mounted()) return;
    _deps.refreshListShelfPresence();
    await refreshVisibleListShelf(channel);
  }

  /// Create an empty list from the Sources picker — the discoverable path for
  /// someone who hasn't long-pressed a channel yet. Selects it afterwards so
  /// the (empty) shelf explains how to fill it.
  Future<void> promptCreateList() async {
    final name = await showIptvListNameDialog(
      context: _deps.context(),
      title: 'New list',
      confirmLabel: 'Create',
      existingNames: [for (final list in _membershipState.lists) list.name],
    );
    if (name == null || !_deps.mounted()) return;
    final id = await IptvFavoritesStorage.createIptvList(name);
    if (!_deps.mounted()) return;
    await loadFavorites();
    if (!_deps.mounted()) return;
    _deps.refreshListShelfPresence();
    for (final playlist in _settingsState.playlists) {
      if (playlist.customListId == id) {
        _deps.onPlaylistChanged(playlist);
        break;
      }
    }
  }

  /// Rebuild the shelf the user is looking at when [channel] just left it —
  /// a row the picker removed can't stay on screen claiming otherwise.
  ///
  /// Narrow on purpose. A reload disposes every row's focus node (see
  /// [_loadPlaylist]), so it only earns that cost when the visible grid is
  /// genuinely wrong; adding a channel to some OTHER list changes nothing
  /// here. And deliberately NOT via _loadSettings, which re-derives the
  /// landing selection and would yank the user off the source they are on.
  Future<void> refreshVisibleListShelf(IptvChannel channel) async {
    final playlist = _settingsState.selectedPlaylist;
    if (playlist == null) return;
    final listId = playlist.isFavorites
        ? IptvFavoritesStorage.iptvFavoritesListId
        : playlist.customListId;
    if (listId == null) return;
    final stillIn =
        _membershipState.membership[channel.url]?.contains(listId) ?? false;
    if (stillIn) return;
    final onScreen = _catalogState.allChannels.any((c) => c.url == channel.url);
    if (!onScreen) return;
    await _deps.loadPlaylist(playlist);
  }
}
