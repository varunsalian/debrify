import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

typedef IptvCatalogRefreshDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvSettingsState settingsState,
  IptvStatusState statusState,
  // TEMP(iptv): _applyFilters -> IptvFiltersSection.applyFilters (step 4).
  void Function() applyFilters,
  List<String> Function(CatalogSnapshot snap, List<CatalogGroup> groups)
  deriveCategories,
  Future<void> Function() loadFavorites,
  DbChannelList Function(CatalogSnapshot snap, {String? group, String? search})
  makeDbList,
  bool Function() mounted,
  Future<void> Function(
    IptvPlaylist playlist,
    int ticket,
    IptvParseResult result, {
    bool migrateFavorites,
    String? cacheKey,
  })
  presentCatalog,
  bool Function(IptvPlaylist playlist, String contentType, int ticket)
  revalidateSuperseded,
  // TEMP(iptv): _rowAttached -> IptvRowProjection.rowAttached (step 6).
  bool Function(IptvChannel channel) rowAttached,
  StateSetter setState,
  void Function(
    CatalogChipState state,
    String message, {
    Duration? autoHide,
    ChipOwner owner,
  })
  showChip,
  // TEMP(iptv): _updateEpgContext -> IptvGuideContext.updateEpgContext (step 4).
  void Function(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket, {
    bool quiet,
  })
  updateEpgContext,
});

class IptvCatalogRefresh {
  final IptvCatalogRefreshDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvSettingsState _settingsState;
  final IptvStatusState _statusState;

  IptvCatalogRefresh(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _settingsState = _deps.settingsState,
      _statusState = _deps.statusState;

  /// Background refresh for a DB-backed catalog. The fetch itself ingests a
  /// new generation on the worker; this decides what the UI does with it:
  /// identical content → re-pin the facades (zero disruption, the DB-mode
  /// equivalent of the identity reconcile), changed content → swap facades
  /// and run the same focus-repair the materialized path uses.
  Future<void> revalidateDbCatalog(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket,
  ) async {
    final target = IptvCatalogDb.captureWriteTarget();
    IptvCatalogDb.markRevalidateStarted(cacheKey);
    try {
      await revalidateDbCatalogInner(playlist, contentType, cacheKey, ticket);
    } finally {
      // Cleared on EVERY outcome this code can see, so a surviving marker
      // means one thing only: the device died mid-refresh. See
      // IptvCatalogDb.revalidateInterrupted.
      if (target != null) {
        try {
          await IptvCatalogDb.runWithWriteTarget(target, () async {
            IptvCatalogDb.markRevalidateFinished(cacheKey);
          });
        } catch (_) {
          // The old connection is retired; preserve its interrupted marker.
        }
      }
    }
  }

  void onCatalogRefreshed() {
    if (!_deps.mounted() ||
        _catalogState.applyingCatalogRefresh ||
        !IptvCatalogDb.isOpen) {
      return;
    }
    final playlist = _settingsState.selectedPlaylist;
    if (playlist == null || _catalogState.dbSnapshot == null) return;
    final key = IptvCatalogKey.forPlaylist(
      playlist,
      _catalogState.selectedContentType,
    );
    if (key == null) return;
    _catalogState.applyingCatalogRefresh = true;
    unawaited(
      revalidateDbCatalogInner(
            playlist,
            _catalogState.selectedContentType,
            key,
            _catalogState.loadTicket,
            usePublishedSnapshot: true,
          )
          .catchError((Object error) {
            debugPrint(
              'IPTV catalog presentation refresh failed (${error.runtimeType})',
            );
          })
          .whenComplete(() => _catalogState.applyingCatalogRefresh = false),
    );
  }

  Future<void> revalidateDbCatalogInner(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket, {
    bool usePublishedSnapshot = false,
  }) {
    final key = '$cacheKey#$ticket';
    final existing = _catalogState.catalogPresentationJobs[key];
    if (existing != null) return existing;
    final future = applyDbCatalogRefresh(
      playlist,
      contentType,
      cacheKey,
      ticket,
      usePublishedSnapshot: usePublishedSnapshot,
    );
    final tracked = future.whenComplete(
      () => _catalogState.catalogPresentationJobs.remove(key),
    );
    _catalogState.catalogPresentationJobs[key] = tracked;
    return tracked;
  }

  Future<void> applyDbCatalogRefresh(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket, {
    bool usePublishedSnapshot = false,
  }) async {
    _statusState.chipShowTimer?.cancel();
    _statusState.chipShowTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_deps.revalidateSuperseded(playlist, contentType, ticket)) {
        _deps.showChip(CatalogChipState.updating, 'Updating list…');
      }
    });

    IptvParseResult result;
    try {
      final published = usePublishedSnapshot
          ? IptvCatalogDb.snapshot(cacheKey)
          : null;
      result = published == null
          ? await IptvCatalogRefreshService.instance.refreshCatalog(
              playlist,
              contentType,
            )
          : IptvParseResult(
              channels: const [],
              categories: published.categories,
              ingest: CatalogIngestReceipt(
                catalogKey: cacheKey,
                channelCount: published.channelCount,
                contentDigest: published.contentDigest,
              ),
            );
    } catch (e) {
      result = IptvParseResult(
        channels: const [],
        categories: const [],
        error: '$e',
      );
    }
    _statusState.chipShowTimer?.cancel();
    final chipWasVisible = _statusState.chipState == CatalogChipState.updating;

    if (_deps.revalidateSuperseded(playlist, contentType, ticket)) return;

    final receipt = result.ingest;
    if (result.hasError || (receipt == null && result.channels.isEmpty)) {
      _deps.showChip(
        CatalogChipState.failure,
        'Couldn\'t refresh — showing saved list',
        autoHide: const Duration(milliseconds: 3500),
      );
      return;
    }

    if (receipt == null) {
      // The DB flag flipped off while the fetch was in flight — present the
      // materialized result through the classic path.
      await _deps.presentCatalog(playlist, ticket, result, cacheKey: cacheKey);
      return;
    }

    final old = _catalogState.dbSnapshot;
    final fresh = IptvCatalogDb.snapshot(cacheKey);
    if (fresh == null) return;

    final oldFirstLive = old?.page(offset: 0, limit: 1, live: true);
    final freshFirstLive = fresh.page(offset: 0, limit: 1, live: true);
    final numberingAdded =
        oldFirstLive?.isNotEmpty == true &&
        oldFirstLive!.first.channelNumber == null &&
        freshFirstLive.isNotEmpty &&
        freshFirstLive.first.channelNumber != null;
    if (old != null &&
        fresh.contentDigest == old.contentDigest &&
        !numberingAdded) {
      // Channel rows unchanged: move the generation pin forward and keep
      // every resident page, instance, focus node and scroll offset exactly
      // as they are.
      final all = _catalogState.allChannels;
      final filtered = _catalogState.filteredChannels;
      if (all is DbChannelList) all.repin(fresh);
      if (filtered is DbChannelList) filtered.repin(fresh);
      _catalogState.dbSnapshot = fresh;
      // The digest covers channel rows only — the provider's own category
      // LIST can still have changed (renamed/reordered categories). The
      // materialized path catches that with its listEquals check; mirror it
      // so the chips never go stale.
      if (!listEquals(fresh.categories, old.categories)) {
        final groups = await IptvCatalogDb.groupsAsync(fresh);
        if (_deps.revalidateSuperseded(playlist, contentType, ticket)) return;
        final categories = _deps.deriveCategories(fresh, groups);
        final selectedVanished =
            _catalogState.selectedCategory != null &&
            !categories.contains(_catalogState.selectedCategory);
        _deps.setState(() {
          _catalogState.categories = categories;
          _catalogState.dbGroupCounts = {
            for (final g in groups)
              if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
          };
          if (selectedVanished) _catalogState.selectedCategory = null;
        });
        // Falling back to All changes the row set — rebuild the filter.
        if (selectedVanished) _deps.applyFilters();
      }
      if (chipWasVisible) {
        _deps.showChip(
          CatalogChipState.success,
          'Up to date',
          autoHide: const Duration(milliseconds: 1800),
        );
      }
      return;
    }

    // Real change. Star migration first, against the fresh rows, so
    // favorites line up on the first paint — computed on a worker from the
    // catalog rows, never by walking a facade here.
    final freshAll = _deps.makeDbList(fresh);
    await IptvFavoritesStorage.reconcileIptvFavoriteUrlsForCatalog(
      fresh.catalogKey,
    );
    await _deps.loadFavorites();
    if (_deps.revalidateSuperseded(playlist, contentType, ticket)) return;

    // Capture the DPAD position before the swap.
    IptvChannel? focusedChannel;
    for (final entry in _focusState.cardFocusNodes.entries) {
      if (entry.value.hasFocus) {
        focusedChannel = entry.key;
        break;
      }
    }
    final outgoing = _catalogState.filteredChannels;
    final oldFilteredIndex = focusedChannel == null
        ? -1
        : (outgoing is DbChannelList
              ? (outgoing.indexOfInstance(focusedChannel) ?? -1)
              : outgoing.indexOf(focusedChannel));

    final added = (fresh.channelCount - (old?.channelCount ?? 0)).clamp(
      0,
      1 << 30,
    );

    final groups = await IptvCatalogDb.groupsAsync(fresh);
    if (_deps.revalidateSuperseded(playlist, contentType, ticket)) return;
    final categories = _deps.deriveCategories(fresh, groups);
    _deps.setState(() {
      _catalogState.dbSnapshot = fresh;
      _catalogState.dbGroupCounts = {
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
      };
      _catalogState.allChannels = freshAll;
      _catalogState.categories = categories;
      if (_catalogState.selectedCategory != null &&
          !categories.contains(_catalogState.selectedCategory)) {
        _catalogState.selectedCategory = null;
      }
    });
    _deps.applyFilters();

    // Post-frame: repair focus if it fell to a bare scope, then retire the
    // outgoing generation's now-detached nodes — same rules and ordering as
    // the materialized revalidate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      if (focusedChannel != null && ticket == _catalogState.loadTicket) {
        final primary = FocusManager.instance.primaryFocus;
        final focusLost = primary == null || primary is FocusScopeNode;
        if (focusLost) {
          FocusNode? target;
          if (_catalogState.filteredChannels.isNotEmpty) {
            final idx = oldFilteredIndex < 0
                ? 0
                : oldFilteredIndex.clamp(
                    0,
                    _catalogState.filteredChannels.length - 1,
                  );
            final candidate = _catalogState.filteredChannels[idx];
            if (_deps.rowAttached(candidate)) {
              target = _focusState.cardFocusNodes[candidate];
            }
          }
          if (target == null) {
            for (final entry in _focusState.cardFocusNodes.entries) {
              if (_deps.rowAttached(entry.key)) {
                target = entry.value;
                break;
              }
            }
          }
          (target ?? _focusState.playlistFilterFocusNode).requestFocus();
        }
      }
      final detached = [
        for (final entry in _focusState.cardFocusNodes.entries)
          if (_focusState.detachedRows.contains(entry.key) &&
              !entry.value.hasFocus)
            entry.key,
      ];
      for (final channel in detached) {
        _focusState.detachedRows.remove(channel);
        _focusState.cardFocusNodes.remove(channel)?.dispose();
      }
    });
    WidgetsBinding.instance.scheduleFrame();

    // Guide rebind against the CURRENT stored configuration, mirroring the
    // materialized revalidate. No snapshot write — the DB is the store.
    final storedPlaylists = await IptvPlaylistStorage.getIptvPlaylists(
      forSettings: false,
    );
    if (_deps.revalidateSuperseded(playlist, contentType, ticket)) return;
    IptvPlaylist? storedPlaylist;
    for (final p in storedPlaylists) {
      if (p.id == playlist.id) {
        storedPlaylist = p;
        break;
      }
    }
    final displayed = IptvParseResult(
      channels: _catalogState.allChannels,
      categories: _catalogState.categories,
      epgUrl: fresh.epgUrl,
    );
    _catalogState.lastLoadResult = displayed;
    if (storedPlaylist != null &&
        IptvCatalogKey.forPlaylist(storedPlaylist, contentType) == cacheKey) {
      _deps.updateEpgContext(storedPlaylist, displayed, ticket, quiet: true);
    }

    _deps.showChip(
      CatalogChipState.success,
      added > 0 ? 'Updated • $added new' : 'List updated',
      autoHide: const Duration(milliseconds: 2200),
    );
  }
}
