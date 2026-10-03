import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_landing_policy.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/material.dart';

typedef IptvFiltersSectionDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  void Function() beginLoadStatus,
  // TEMP(iptv): _clearPreview -> IptvPreviewTuning.clearPreview (step 6).
  void Function() clearPreview,
  // TEMP(iptv): _focusNodeFor -> IptvRowProjection.focusNodeFor (step 6).
  FocusNode Function(IptvChannel channel) focusNodeFor,
  // TEMP(iptv): _focusSpotlightContentEntry -> IptvSpotlightFocus.focusSpotlightContentEntry (step 6).
  void Function() focusSpotlightContentEntry,
  bool Function() isTelevision,
  Future<void> Function(IptvPlaylist playlist, {bool userRequested})
  loadPlaylist,
  DbChannelList Function(CatalogSnapshot snap, {String? group, String? search})
  makeDbList,
  bool Function() mounted,
  String Function() searchQuery,
  StateSetter setState,
});

class IptvFiltersSection {
  final IptvFiltersSectionDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvFiltersSection(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  String? get effectiveCategory =>
      _deps.searchQuery().isNotEmpty ? null : _catalogState.selectedCategory;

  void onChannelOrderChanged() {
    final playlist = _settingsState.selectedPlaylist;
    final change = IptvChannelOrderSignal.latest;
    if (!_deps.mounted() || playlist == null || change == null) return;
    final affected = switch (change.scope) {
      IptvChannelOrderScope.list =>
        (playlist.isFavorites &&
                change.target == IptvFavoritesStorage.iptvFavoritesListId) ||
            playlist.customListId == change.target,
      IptvChannelOrderScope.source =>
        change.target.isEmpty || playlist.id == change.target,
      IptvChannelOrderScope.catalog =>
        change.target.isEmpty ||
            IptvCatalogKey.forCategoryOrder(
                  playlist,
                  _catalogState.selectedContentType,
                ) ==
                change.target,
    };
    if (affected) unawaited(_deps.loadPlaylist(playlist));
  }

  void applyFilters() {
    _catalogState.spotlightViewGeneration++;
    // A programme cursor belongs to the outgoing projection. The timeline
    // will publish the reconciled row/programme after its next frame.
    _previewState.spotlightProgrammeShown.value = null;
    // DB-backed catalog: the filter IS the query — a new facade with the
    // category/search folded into its SQL. Same substring-over-name+group
    // semantics as searchChannels (the search_key column is the same
    // haystack IptvChannel.searchKey builds).
    final snap = _catalogState.dbSnapshot;
    if (snap != null) {
      _deps.setState(() {
        _catalogState.filteredChannels = _deps.makeDbList(
          snap,
          group: effectiveCategory,
          search: _deps.searchQuery().isEmpty ? null : _deps.searchQuery(),
        );
      });
      // A new facade mints new instances, so the outgoing filter's rows can
      // never be handed out again — their focus nodes would otherwise pile
      // up until the next full reload (the materialized path reuses
      // instances across filters and doesn't have this). Post-frame, after
      // the new rows are built: retire everything detached and unfocused.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        final orphans = [
          for (final entry in _focusState.cardFocusNodes.entries)
            if (_focusState.detachedRows.contains(entry.key) &&
                !entry.value.hasFocus)
              entry.key,
        ];
        for (final channel in orphans) {
          _focusState.detachedRows.remove(channel);
          _focusState.cardFocusNodes.remove(channel)?.dispose();
        }
      });
      return;
    }

    var channels = _catalogState.allChannels;

    // Filter by category
    if (effectiveCategory != null) {
      channels = _settingsState.iptvService.filterByCategory(
        channels,
        effectiveCategory,
      );
    }

    // Filter by search query
    if (_deps.searchQuery().isNotEmpty) {
      channels = _settingsState.iptvService.searchChannels(
        channels,
        _deps.searchQuery(),
      );
    }

    _deps.setState(() {
      _catalogState.filteredChannels = channels;
    });
  }

  void onPlaylistChanged(IptvPlaylist? playlist, {bool focusContent = false}) {
    if (playlist == null) return;
    if (playlist == _settingsState.selectedPlaylist) {
      // Re-picking the current source shouldn't reload, but from the rail it
      // still means "take me to the list" — collapse the rail and focus the
      // already-loaded content instead of a dead OK press.
      if (focusContent) {
        if (_selectionState.spotlightLayoutMode !=
            IptvSpotlightLayoutMode.classic) {
          _deps.focusSpotlightContentEntry();
          return;
        }
        _focusState.focusContentAfterLoad = true;
        consumeContentFocusRequest();
      }
      return;
    }

    // A pending content-type load belongs to the outgoing playlist.
    _selectionState.contentTypeDebounce?.cancel();
    // Honored by the present paths once the new list is on screen. Only the
    // rail/picker set it — a dropdown or programmatic switch keeps focus
    // where it was.
    _focusState.focusContentAfterLoad = focusContent;
    _deps.setState(() {
      _settingsState.selectedPlaylist = playlist;
      _catalogState.selectedCategory = null;
      if (playlist.isXtreamCodes) {
        _catalogState.selectedContentType = 'live';
      }
    });

    _deps.loadPlaylist(playlist);
  }

  /// Move DPAD focus into the content pane after a rail-initiated playlist
  /// switch, which collapses the source rail's overlay. Post-frame so the
  /// grid's first row (and its lazily-created focus node) exists; falls back
  /// to the in-pane filter row when the new catalog is empty or errored, so
  /// focus never strands on the collapsing rail.
  void consumeContentFocusRequest() {
    if (!_focusState.focusContentAfterLoad) return;
    _focusState.focusContentAfterLoad = false;
    if (!_deps.isTelevision() &&
        _selectionState.spotlightLayoutMode ==
            IptvSpotlightLayoutMode.classic) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      if (_catalogState.filteredChannels.isNotEmpty) {
        if (_selectionState.spotlightLayoutMode !=
                IptvSpotlightLayoutMode.classic &&
            _focusState.spotlightTimelineController.focusFirstChannel()) {
          return;
        }
        _deps.focusNodeFor(_catalogState.filteredChannels.first).requestFocus();
      } else if (_selectionState.spotlightLayoutMode !=
              IptvSpotlightLayoutMode.classic &&
          _focusState.categoryFilterFocusNode.canRequestFocus) {
        _focusState.categoryFilterFocusNode.requestFocus();
      } else {
        _focusState.playlistFilterFocusNode.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void onContentTypeChanged(String contentType) {
    if (contentType == _catalogState.selectedContentType) return;

    _deps.setState(() {
      _catalogState.selectedContentType = contentType;
      _catalogState.selectedCategory = null;
      // The outgoing type's rows leave NOW, not when the debounced load
      // lands: they'd otherwise render for the debounce window under the new
      // type's layout flag (_showsPosterRows flips immediately), and a tap in
      // that window would play an item of a type the filter no longer shows.
      // Mirrors the reset _loadPlaylist performs; the spinner covers the gap
      // exactly as it did when the load was synchronous.
      _catalogState.isLoading = true;
      // The spinner is up NOW but the load is 350ms away, so the status must
      // reset with it — otherwise this window renders the previous load's
      // phase and byte count against a stale start time, with the ticker
      // already stopped: frozen, wrong text rather than merely old.
      _deps.beginLoadStatus();
      _catalogState.allChannels = [];
      _catalogState.filteredChannels = [];
      _catalogState.categories = [];
      _catalogState.dbSnapshot = null;
      _catalogState.dbGroupCounts = const {};
      _membershipState.progressByUrl = {};
      _selectionState.scheduleChannel = null;
    });
    _deps.clearPreview();

    // Debounced: the classic layout's toggle CYCLES Live → Movies → Series,
    // so reaching a non-adjacent type means passing through one the user
    // never wanted — a full playlist load (focus-node disposal, possibly a
    // multi-second uncached panel fetch) per intermediate step. Let the
    // selection settle first; only the type the user stops on loads. Short
    // enough to be imperceptible on a single direct pick (the TV dropdown
    // path).
    _selectionState.contentTypeDebounce?.cancel();
    _selectionState.contentTypeDebounce = Timer(
      const Duration(milliseconds: 350),
      () {
        if (!_deps.mounted()) return;
        if (_settingsState.selectedPlaylist != null) {
          _deps.loadPlaylist(_settingsState.selectedPlaylist!);
        }
      },
    );
  }

  void onCategoryChanged(String? category) {
    _catalogState.categoryManuallyChosen = true;
    _deps.setState(() => _catalogState.selectedCategory = category);
    applyFilters();
  }

  /// The category a fresh load should land on when nothing is picked yet:
  /// the saved default when it still exists in [categories], else the first
  /// category in display order — so the list opens on the user's #1 category
  /// rather than the provider's raw channel order. Null (land on All) when
  /// the user already picked a chip this load, a search is active (a source
  /// switch mid-search must keep searching everything), or the source has no
  /// durable identity to save a choice under ([orderKey] null: virtual
  /// shelves, Stremio addons).
  ///
  /// Only a load's FIRST present may seed ([landingSeedArmed]); the
  /// revalidate paths share these present functions and must never re-seed —
  /// the vanished-category resets (hidden, renamed, removed by the provider)
  /// keep their fall-back-to-All behavior, because re-seeding mid-browse
  /// would yank the view.
  String? landingCategory(String? orderKey, List<String> categories) =>
      !_catalogState.landingSeedArmed
      ? null
      : IptvLandingPolicy.landingCategoryFor(
          orderKey: orderKey,
          categories: categories,
          manuallyChosen: _catalogState.categoryManuallyChosen,
          searching: _deps.searchQuery().isNotEmpty,
        );
}
