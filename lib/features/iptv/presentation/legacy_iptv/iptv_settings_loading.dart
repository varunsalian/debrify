import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/iptv_source_stats.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsLoadingDeps = ({
  IptvCatalogState catalogState,
  IptvMembershipState membershipState,
  IptvPreviewState previewState,
  IptvRecordingState recordingState,
  IptvSettingsState settingsState,
  IptvPlaylist Function(IptvListMeta list) listPlaylist,
  Future<void> Function(IptvPlaylist playlist, {bool userRequested})
  loadPlaylist,
  bool Function() mounted,
  // TEMP(iptv): _retunePreview -> IptvPreviewTuning.retunePreview (step 6).
  void Function(IptvChannel channel) retunePreview,
  StateSetter setState,
  // TEMP(iptv): _stopPreviewPlayback -> IptvPreviewTuning.stopPreviewPlayback (step 6).
  void Function() stopPreviewPlayback,
});

class IptvSettingsLoading {
  final IptvSettingsLoadingDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvMembershipState _membershipState;
  final IptvPreviewState _previewState;
  final IptvRecordingState _recordingState;
  final IptvSettingsState _settingsState;

  IptvSettingsLoading(this._deps)
    : _catalogState = _deps.catalogState,
      _membershipState = _deps.membershipState,
      _previewState = _deps.previewState,
      _recordingState = _deps.recordingState,
      _settingsState = _deps.settingsState;

  void onStremioAddonsChanged() {
    if (_deps.mounted()) loadSettings();
  }

  /// Guarded entry point — see [settingsError]. Every caller (initState, the
  /// addon-changed listener, returning from Settings, Retry) goes through here
  /// so no path can reintroduce the silent spinner.
  Future<void> loadSettings({bool forceReload = false}) async {
    try {
      await loadSettingsInner(forceReload: forceReload);
    } catch (e, st) {
      debugPrint('IPTV: settings load failed: $e\n$st');
      if (!_deps.mounted()) return;
      // Deliberately NOT setting _settingsLoaded: the page below this gate
      // assumes a loaded playlist set. Failing here keeps the failure
      // contained to the gate, which now renders the reason and a Retry.
      _deps.setState(() => _settingsState.settingsError = '$e');
    }
  }

  Future<void> loadSettingsInner({bool forceReload = false}) async {
    var playlists = await IptvPlaylistStorage.getIptvPlaylists(
      forSettings: false,
    );
    final defaultPlaylistId =
        await IptvPlaylistStorage.getIptvDefaultPlaylist();
    // Cockpit look. Read on every pass so returning from Settings (which
    // re-enters here) adopts a changed style in the same setState as
    // everything else — no separate listener, no style flash.
    final iptvStyle = IptvStyle.fromPref(
      await IptvAppearanceStorage.getIptvStyle(),
    );
    final channelPreviewEnabled =
        await IptvAppearanceStorage.getIptvChannelPreviewEnabled();

    // Installed Stremio addons with live-TV catalogs appear as (non-stored)
    // virtual playlists after the user's own entries.
    final virtualPlaylists = await StremioIptvService.instance
        .getVirtualPlaylists();
    playlists = [...playlists, ...virtualPlaylists];

    // The virtual Favorites playlist leads the picker, then Continue watching,
    // then the user's own lists, then the real providers. Hidden only when
    // there is nothing at all (no playlists, no favorites, no lists), so the
    // add-a-playlist empty state can still do its job.
    //
    // One store read covers both the presence probe and the list rows — the
    // per-list channel counts come back with them.
    final lists = await IptvFavoritesStorage.getIptvLists();
    final hasFavorites = lists.any((l) => l.isFavorites && l.channelCount > 0);
    final customLists = [
      for (final list in lists)
        if (!list.isBuiltin) list,
    ];
    // "Continue watching" earns its slot only while something is actually
    // half-watched — an empty shelf in the picker is just noise. Custom lists
    // stay visible even when empty: the user made them on purpose, and an
    // empty one is where they go to fill it.
    final continueWatching = await IptvHistoryStorage.getIptvContinueWatching();
    final hasContinue = continueWatching.isNotEmpty;
    if (hasFavorites || customLists.isNotEmpty || playlists.isNotEmpty) {
      playlists = [
        IptvMembershipState.favoritesPlaylist,
        if (hasContinue) IptvMembershipState.continuePlaylist,
        for (final list in customLists) _deps.listPlaylist(list),
        ...playlists,
      ];
    }

    if (!_deps.mounted()) return;

    // Determine the new selected playlist. The playlist the user starred as
    // "Default" in Settings wins: it is the one landing they asked for out
    // loud, so it outranks the Favorites shelf. With no usable default, at
    // least one starred channel makes Favorites the landing selection;
    // otherwise the first real provider (never landing on an empty Favorites
    // view).
    IptvPlaylist? newSelectedPlaylist;
    IptvPlaylist? firstRealPlaylist;
    for (final p in playlists) {
      // No virtual shelf is a "real" playlist to fall back to — each can be
      // empty or vanish entirely between visits, and landing on an empty
      // custom list reads exactly as broken as landing on empty Favorites.
      // (Stremio addon shelves stay eligible: they are a remote catalog with
      // content of their own, not a view over stored rows.)
      if (!p.isFavorites && !p.isContinueWatching && !p.isCustomList) {
        firstRealPlaylist = p;
        break;
      }
    }
    // Only a default that still resolves to a present provider counts — a
    // stale id (its playlist deleted elsewhere, an addon shelf whose addon is
    // uninstalled) must fall through rather than outrank Favorites.
    IptvPlaylist? defaultPlaylist;
    if (defaultPlaylistId != null) {
      for (final p in playlists) {
        if (p.id == defaultPlaylistId) {
          defaultPlaylist = p;
          break;
        }
      }
    }
    if (defaultPlaylist != null) {
      newSelectedPlaylist = defaultPlaylist;
    } else if (hasFavorites) {
      newSelectedPlaylist = IptvMembershipState.favoritesPlaylist;
    } else if (playlists.isNotEmpty) {
      newSelectedPlaylist = firstRealPlaylist ?? playlists.first;
    }

    // Check if playlist changed
    final playlistChanged =
        _settingsState.selectedPlaylist?.id != newSelectedPlaylist?.id;

    // Rail counts: a handful of indexed reads against the already-open
    // catalog. Skipped entirely when the DB isn't up — the rail just shows
    // no numbers, never a spinner.
    final sourceCounts = <String, int>{};
    if (IptvCatalogDb.isOpen) {
      for (final p in playlists) {
        if (p.isVirtual) continue;
        try {
          final stats = IptvSourceStatsLoader.read(p);
          if (stats.cached) sourceCounts[p.id] = stats.total;
        } catch (_) {
          // A closed/failed DB read leaves this source uncounted, nothing more.
        }
      }
    }

    final previewWasEnabled = _settingsState.channelPreviewEnabled;
    _deps.setState(() {
      _settingsState.iptvStyle = iptvStyle;
      _settingsState.channelPreviewEnabled = channelPreviewEnabled;
      _recordingState.sourceCounts = sourceCounts;
      _recordingState.continueWatchingCount = continueWatching.length;
      _settingsState.playlists = playlists;
      _settingsState.settingsLoaded = true;
      _settingsState.selectedPlaylist = newSelectedPlaylist;
      // Adopt the rows this pass just read. Returning from Settings goes
      // through here and NOT through _loadFavorites (a catalog reload only
      // happens when the selected playlist changed), so without this the
      // first list a user creates there would leave long-press still
      // toggling Favorites, and a deleted one would keep a picker pointed at
      // a row that no longer exists.
      _membershipState.lists = lists;
    });

    // Returning from Settings must release an already-open preview
    // immediately. Re-enabling retunes the still-selected channel so the
    // setting takes effect without requiring an extra focus move.
    if (!channelPreviewEnabled) {
      _deps.stopPreviewPlayback();
    } else if (!previewWasEnabled) {
      final shown = _previewState.previewShown.value;
      if (shown != null) _deps.retunePreview(shown);
    }

    // Only reload playlist if it changed or forced, or if we have no channels
    // loaded AND no load is already producing them — "_allChannels.isEmpty"
    // alone is true for a first load's whole duration, and re-entry here
    // (addons-changed listener, settings return) used to stack a second full
    // pipeline on top of the running one. Forced/changed loads still start
    // immediately: bumping the ticket orphans the in-flight run's result.
    if (_settingsState.selectedPlaylist != null &&
        (forceReload ||
            playlistChanged ||
            (_catalogState.allChannels.isEmpty &&
                _catalogState.inFlightLoadTicket == null))) {
      // forceReload follows a settings edit — the user just changed this
      // provider, so a suppressed refresh must not outrank that.
      _deps.loadPlaylist(
        _settingsState.selectedPlaylist!,
        userRequested: forceReload,
      );
    }
  }

  /// The error screen's Retry. Re-reads the stored playlists before loading:
  /// the in-memory record's connection authority can be stale — saving IPTV
  /// sources anywhere (the main Settings page included) rewrites the whole
  /// collection and bumps EVERY source's authorization revision, not just the
  /// edited one — and replaying the same object can then never succeed
  /// ("Connection authority changed" on every press).
  Future<void> retryLoad() async {
    final current = _settingsState.selectedPlaylist;
    if (current == null) return;
    var target = current;
    if (!current.isVirtual) {
      try {
        final stored = await IptvPlaylistStorage.getIptvPlaylists(
          forSettings: false,
        );
        final byId = {for (final p in stored) p.id: p};
        if (!_deps.mounted()) return;
        _deps.setState(() {
          // Refresh every real entry the rail holds too — they were all
          // invalidated by the same collection write, so a tap on a sibling
          // source would otherwise fail the same way.
          _settingsState.playlists = [
            for (final p in _settingsState.playlists)
              if (p.isVirtual) p else byId[p.id] ?? p,
          ];
          target = byId[current.id] ?? current;
          _settingsState.selectedPlaylist = target;
        });
      } catch (_) {
        // Re-read failed; retry with the in-memory record. _loadPlaylist
        // lands any failure back in this same error state.
      }
    }
    await _deps.loadPlaylist(target, userRequested: true);
  }
}
