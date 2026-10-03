import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/iptv_load_phase.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:flutter/material.dart';

typedef IptvCatalogLoadingDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  IptvStatusState statusState,

  void Function(int ticket, List<IptvChannel> channels, List<String> categories)
  applyProgressiveBatch,
  void Function() beginLoadStatus,

  Future<IptvParseResult> Function() buildContinueResult,

  Future<IptvParseResult> Function(String listId) buildListResult,

  void Function() clearPreview,

  void Function() consumeContentFocusRequest,
  void Function() endLoadStatus,
  Future<IptvParseResult> Function(
    IptvPlaylist playlist,
    String contentType,
    int ticket,
  )
  fetchCatalogFromNetwork,
  bool Function() mounted,
  void Function(int ticket, String phase, {int? bytes, int? totalBytes})
  onLoadPhase,
  Future<void> Function(
    IptvPlaylist playlist,
    int ticket,
    IptvParseResult result, {
    bool migrateFavorites,
    String? cacheKey,
  })
  presentCatalog,
  Future<void> Function(
    IptvPlaylist playlist,
    int ticket,
    CatalogSnapshot snap, {
    String? warning,
    bool migrateFavorites,
  })
  presentDbCatalog,
  Future<void> Function(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket, {
    required bool userRequested,
  })
  runCatalogMaintenance,
  Future<bool> Function(String cacheKey, int ticket) runPendingMigrations,
  StateSetter setState,
});

class IptvCatalogLoading {
  final IptvCatalogLoadingDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;
  final IptvStatusState _statusState;

  IptvCatalogLoading(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState,
      _statusState = _deps.statusState;

  /// [userRequested] marks a load the user explicitly asked for (the error
  /// screen's Retry, a settings round-trip). Such a load ignores the
  /// interrupted-refresh backoff — that guard exists to stop the page from
  /// re-running a refresh the device did not survive, not to override someone
  /// deliberately asking for fresh data.
  Future<void> loadPlaylist(
    IptvPlaylist playlist, {
    bool userRequested = false,
  }) async {
    final ticket = ++_catalogState.loadTicket;
    _catalogState.inFlightLoadTicket = ticket;
    try {
      await loadPlaylistInner(playlist, ticket, userRequested: userRequested);
    } catch (e, st) {
      // This method is fired-and-forgotten from initState, dropdowns and
      // Retry, and there is no zone guard above it — an escape here used to
      // vanish silently, leaving `_isLoading = true` and the 1 Hz status
      // ticker running forever: a permanent fake spinner. Land every failure
      // (DB open, SQL, a malformed stored playlist) in the real error state,
      // which has a Retry.
      debugPrint('IPTV: playlist load failed: $e\n$st');
      if (_deps.mounted() && ticket == _catalogState.loadTicket) {
        IptvEpgService.instance.clearM3uEpgContext();
        _deps.endLoadStatus();
        _deps.setState(() {
          _catalogState.isLoading = false;
          _catalogState.isLoadingMore = false;
          _catalogState.errorMessage = 'Could not load this playlist.\n$e';
        });
        _deps.consumeContentFocusRequest();
      }
    } finally {
      if (_catalogState.inFlightLoadTicket == ticket) {
        _catalogState.inFlightLoadTicket = null;
      }
    }
  }

  Future<void> loadPlaylistInner(
    IptvPlaylist playlist,
    int ticket, {
    bool userRequested = false,
  }) async {
    _catalogState.lastProgressiveApply = null;
    _deps.beginLoadStatus();
    // A lingering refresh chip belongs to the outgoing playlist.
    _statusState.chipShowTimer?.cancel();
    _statusState.chipHideTimer?.cancel();
    _deps.setState(() {
      _catalogState.isLoading = true;
      _catalogState.isLoadingMore = false;
      _catalogState.errorMessage = null;
      _catalogState.allChannels = [];
      _catalogState.filteredChannels = [];
      _catalogState.categories = [];
      _catalogState.selectedCategory = null;
      // A fresh load may seed a landing category again; the outgoing
      // playlist's explicit pick doesn't carry over.
      _catalogState.categoryManuallyChosen = false;
      _catalogState.landingSeedArmed = true;
      _statusState.chipState = CatalogChipState.hidden;
      _statusState.chipOwner = ChipOwner.none;
      _catalogState.dbSnapshot = null;
      _catalogState.dbGroupCounts = const {};
      // The outgoing catalog's instances are no use to the incoming one.
      _catalogState.dbInstanceCache.clear();
      _catalogState.dbInstanceCacheKey = null;
      // Positions belong to the outgoing playlist's URLs.
      _membershipState.progressByUrl = {};
      // An open schedule belongs to the outgoing playlist too.
      _selectionState.scheduleChannel = null;
    });

    // Retire the outgoing catalog's focus nodes AFTER the rebuild that
    // unmounts their rows. Disposing them here — while the old rows are still
    // mounted (the setState above only marks dirty) — would unfocus the
    // primary node into a scope that next frame has zero focusable children:
    // the remote goes dead on the spinner, which on TV reads as a freeze.
    // (Debug builds also assert "used after being disposed".) The map is
    // cleared NOW so new rows mint fresh nodes; the old nodes' dispose runs
    // post-frame, by which point the rebuild has detached them all.
    final outgoingNodes = List<FocusNode>.of(_focusState.cardFocusNodes.values);
    final contentHadFocus =
        _focusState.spotlightTimelineController.hasFocus ||
        outgoingNodes.any((n) => n.hasFocus);
    _focusState.cardFocusNodes.clear();
    _focusState.detachedRows.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in outgoingNodes) {
        node.dispose();
      }
    });
    // If the user was in the grid when this reload started (content-type
    // switch, post-playback refresh), put them back in it when the new rows
    // land — only rail-initiated switches used to re-home, leaving every
    // other path DPAD-dead.
    if (contentHadFocus) _focusState.focusContentAfterLoad = true;
    // The stage's channel belongs to the outgoing playlist.
    _deps.clearPreview();

    // Serve-stale-while-revalidate: network-backed catalogs (Xtream logins,
    // M3U URLs) render their stored rows instantly — no spinner, works
    // offline — then refresh in the background. First-ever loads (nothing
    // ingested yet) fall through to the blocking path below.
    final contentType = _catalogState.selectedContentType;
    final cacheKey = IptvCatalogKey.forPlaylist(playlist, contentType);

    // ── DB-catalog path ────────────────────────────────────────────────────
    // Cacheable catalogs live in iptv_catalog.db: present the stored rows
    // (paged, constant memory), revalidate in the background when stale.
    if (cacheKey != null) {
      await IptvCatalogDb.open();
      if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
      final snap = IptvCatalogDb.snapshot(cacheKey);
      if (snap != null && snap.channelCount > 0) {
        await _deps.presentDbCatalog(playlist, ticket, snap);
        if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
        // Everything heavy this catalog still needs — pending migration,
        // numbering adoption, an optional refresh — runs as one queued
        // background pipeline that decides for itself what is still required.
        // Started here rather than awaited: the list is already on screen and
        // none of it changes what the user sees.
        unawaited(
          _deps.runCatalogMaintenance(
            playlist,
            contentType,
            cacheKey,
            ticket,
            userRequested: userRequested,
          ),
        );
        return;
      }
      // Never ingested (fresh install / brand-new playlist): fall through to
      // the network fetch below — the parse worker ingests it and hands back
      // a receipt, which _presentCatalog routes to the DB path.
    }

    // Determine source: favorites store, Stremio addon, XC API, local file,
    // or URL
    final IptvParseResult result;
    if (playlist.isFavorites) {
      result = await _deps.buildListResult(
        IptvFavoritesStorage.iptvFavoritesListId,
      );
    } else if (playlist.isCustomList) {
      result = await _deps.buildListResult(playlist.customListId!);
    } else if (playlist.isContinueWatching) {
      result = await _deps.buildContinueResult();
    } else if (playlist.isStremioAddon) {
      final addonId = StremioIptvService.addonIdFromPlaylist(playlist);
      result = addonId == null
          ? const IptvParseResult(
              channels: [],
              categories: [],
              error: 'Broken addon playlist',
            )
          // Progressive: the first catalog page renders as soon as it lands
          // and the list keeps growing batch by batch; switching playlists
          // (or leaving the page) cancels the rest of the walk.
          : await StremioIptvService.instance.fetchChannels(
              addonId,
              isCancelled: () =>
                  !_deps.mounted() || ticket != _catalogState.loadTicket,
              onProgress: (channels, categories) =>
                  _deps.applyProgressiveBatch(ticket, channels, categories),
            );
    } else if (playlist.isLocalFile) {
      result = await _settingsState.iptvService.parseContent(playlist.content!);
    } else {
      // First-ever load of a cacheable catalog included: the whole-catalog
      // WRITE (parse+ingest) runs behind the process-wide gate INSIDE the
      // service — so it still can't overlap the previous page's surviving
      // adoption or refresh — but the network download no longer holds the
      // gate. Wrapping the entire fetch here used to queue every other
      // catalog job behind up to two minutes of a slow server.
      result = await _deps.fetchCatalogFromNetwork(
        playlist,
        contentType,
        ticket,
      );
    }

    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    _deps.onLoadPhase(ticket, IptvLoadPhases.preparing);

    if (result.hasError) {
      // The context lifecycle follows leaving the playlist, not load
      // success: a failed switch must still drop the previous playlist's
      // guide index (memory + wrong capability answers for its URLs).
      IptvEpgService.instance.clearM3uEpgContext();
      _deps.endLoadStatus();
      _deps.setState(() {
        _catalogState.isLoading = false;
        _catalogState.isLoadingMore = false;
        _catalogState.errorMessage = result.error;
      });
      // A rail-initiated switch that errored must still leave the rail: the
      // error (with its Retry) lives in the content pane, and stranding
      // focus on the collapsing rail would trap DPAD. Falls back to the
      // in-pane filter row (channels are empty here).
      _deps.consumeContentFocusRequest();
      return;
    }

    await _deps.presentCatalog(playlist, ticket, result, cacheKey: cacheKey);

    // A first-ever ingest just wrote this catalog, so there is no numbering to
    // adopt and nothing to refresh — but a database that has never been
    // migrated still needs its version stamp and number index. Deliberately
    // last, after that ingest has finished, so the two never overlap.
    if (cacheKey != null &&
        _deps.mounted() &&
        ticket == _catalogState.loadTicket) {
      unawaited(
        IptvCatalogDb.runExclusive(
          () => _deps.runPendingMigrations(cacheKey, ticket),
        ),
      );
    }
  }
}
