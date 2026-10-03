import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

typedef IptvPlaybackRefreshDeps = ({
  IptvCatalogState catalogState,
  IptvMembershipState membershipState,
  IptvRecordingState recordingState,
  IptvSettingsState settingsState,
  void Function() armAndroidRecStateRefresh,
  List<IptvListMeta> Function() customLists,
  Future<void> Function() loadFavorites,
  Future<void> Function(IptvPlaylist playlist, {bool userRequested})
  loadPlaylist,
  Future<void> Function(int ticket, List<IptvChannel> channels) loadProgress,
  bool Function() mounted,
  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  StateSetter setState,
});

class IptvPlaybackRefresh {
  final IptvPlaybackRefreshDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvMembershipState _membershipState;
  final IptvRecordingState _recordingState;
  final IptvSettingsState _settingsState;

  IptvPlaybackRefresh(this._deps)
    : _catalogState = _deps.catalogState,
      _membershipState = _deps.membershipState,
      _recordingState = _deps.recordingState,
      _settingsState = _deps.settingsState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  /// Refresh progress and shelf membership without resetting source selection.
  Future<void> refreshAfterPlayback() async {
    if (!_deps.mounted()) return;
    // Read the shelf ONCE and reuse it below. Each read decodes both the
    // watch-history map and the (potentially large) shared resume map off the
    // UI isolate, and this runs at the exact moment the user lands back on
    // the list — the worst time to do it three times over.
    final items = await IptvHistoryStorage.getIptvContinueWatching();
    if (!_deps.mounted()) return;
    // A recording may have been started (or stopped) from inside the player —
    // the header's record-dot must not lag until the next resume.
    _deps.armAndroidRecStateRefresh();
    await _deps.loadFavorites();
    if (!_deps.mounted()) return;
    refreshContinueShelfPresence(items.length);
    if (!_deps.mounted()) return;

    // A list shelf can have changed under the user while the player was up —
    // both players can add and remove memberships from their own guide. This
    // covers Favorites AND custom lists; without the custom-list arm a
    // channel removed in the native guide stays on screen until a full
    // reload of the page.
    final shelf = _settingsState.selectedPlaylist;
    final shelfListId = (shelf?.isFavorites ?? false)
        ? IptvFavoritesStorage.iptvFavoritesListId
        : shelf?.customListId;
    if (shelfListId != null) {
      final stored = {
        for (final entry in _membershipState.membership.entries)
          if (entry.value.contains(shelfListId)) entry.key,
      };
      final current = {
        for (final channel in _catalogState.allChannels) channel.url,
      };
      if (!setEquals(stored, current)) {
        await _deps.loadPlaylist(shelf!);
        return;
      }
    }

    // The shelf can empty out from under the user — they just finished its
    // last item. Leaving it selected strands the picker: with no matching
    // option the dropdown renders the FIRST option's label instead, so it
    // would read "Favorites" above an empty shelf.
    if (items.isEmpty &&
        (_settingsState.selectedPlaylist?.isContinueWatching ?? false)) {
      final remaining = [
        for (final p in _settingsState.playlists)
          if (!p.isContinueWatching) p,
      ];
      if (remaining.isNotEmpty) {
        _deps.onPlaylistChanged(remaining.first);
        return;
      }
    }

    if (_settingsState.selectedPlaylist?.isContinueWatching ?? false) {
      // Rebuild only when the shelf's membership actually changed — an item
      // finished and dropped off, or a newly watched one arrived. A reload
      // disposes every row's focus node (see _loadPlaylist), so doing it for
      // a mere position bump would scramble DPAD focus to redraw one bar.
      // Compare against the SAME collapsed keys the shelf renders (a series'
      // episodes fold to one sentinel row — see _buildContinueResult), or a
      // series would read as changed on every return and force a reload.
      final fresh = {
        for (final item in items)
          ((item['seriesId'] as String?)?.isNotEmpty ?? false)
              ? 'xtream-series://${(item['playlistId'] as String?) ?? ''}'
                    '/${item['seriesId']}'
              : item['url'] as String,
      };
      final current = {
        for (final channel in _catalogState.allChannels) channel.url,
      };
      if (!setEquals(fresh, current)) {
        await _deps.loadPlaylist(IptvMembershipState.continuePlaylist);
        return;
      }
    }
    await _deps.loadProgress(
      _catalogState.loadTicket,
      _catalogState.allChannels,
    );
  }

  /// Add or drop the Continue-watching entry in the picker to match whether
  /// anything is actually half-watched — so the shelf appears after the very
  /// first movie rather than on the next visit to the page, and disappears
  /// once the last item is finished. Selection is left untouched.
  void refreshContinueShelfPresence(int itemCount) {
    final hasContinue = itemCount > 0;
    final present = _settingsState.playlists.any((p) => p.isContinueWatching);
    if (hasContinue == present &&
        itemCount == _recordingState.continueWatchingCount) {
      return;
    }

    _deps.setState(() {
      _recordingState.continueWatchingCount = itemCount;
      if (hasContinue == present) return;
      if (hasContinue) {
        // Directly after Favorites, or first when there is no Favorites row.
        final favoritesIndex = _settingsState.playlists.indexWhere(
          (p) => p.isFavorites,
        );
        _settingsState.playlists = [..._settingsState.playlists]
          ..insert(favoritesIndex + 1, IptvMembershipState.continuePlaylist);
      } else {
        _settingsState.playlists = [
          for (final p in _settingsState.playlists)
            if (!p.isContinueWatching) p,
        ];
      }
    });
  }

  /// Re-sync the custom-list rows in the picker after the user created,
  /// renamed, deleted or reordered one, without disturbing what they are
  /// looking at. Same reasoning as [_refreshContinueShelfPresence]: going
  /// through _loadSettings would re-derive the landing selection.
  void refreshListShelfPresence() {
    if (!_deps.mounted()) return;
    final desired = [
      for (final list in _customLists) IptvFavorites.listPlaylist(list),
    ];
    final current = [
      for (final p in _settingsState.playlists)
        if (p.isCustomList) p,
    ];
    // Compare names too, not just ids — a rename has to reach the picker.
    String signature(List<IptvPlaylist> entries) =>
        entries.map((p) => '${p.id}\x00${p.name}').join('\x01');
    if (signature(desired) == signature(current)) return;

    // Rebuild in canonical order: Favorites, Continue, lists, real providers.
    final keptVirtuals = [
      for (final p in _settingsState.playlists)
        if (p.isFavorites || p.isContinueWatching) p,
    ];
    final realPlaylists = [
      for (final p in _settingsState.playlists)
        if (!p.isFavorites && !p.isContinueWatching && !p.isCustomList) p,
    ];
    _deps.setState(() {
      _settingsState.playlists = [
        ...keptVirtuals,
        ...desired,
        ...realPlaylists,
      ];
    });

    // The list being viewed can have just been deleted. Leaving it selected
    // strands the picker: with no matching option the dropdown renders the
    // FIRST option's label, so it would read "Favorites" above the wrong grid.
    final selected = _settingsState.selectedPlaylist;
    if (selected != null &&
        !_settingsState.playlists.any((p) => p.id == selected.id)) {
      final fallback = _settingsState.playlists.isEmpty
          ? null
          : _settingsState.playlists.first;
      if (fallback != null) _deps.onPlaylistChanged(fallback);
    }
  }
}
