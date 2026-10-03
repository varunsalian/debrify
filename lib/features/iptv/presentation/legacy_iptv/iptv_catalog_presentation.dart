import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_category_order.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvCatalogPresentationDeps = ({
  IptvCatalogState catalogState,
  // TEMP(iptv): _applyFilters -> IptvFiltersSection.applyFilters (step 4).
  void Function() applyFilters,
  // TEMP(iptv): _consumeContentFocusRequest -> IptvFiltersSection.consumeContentFocusRequest (step 4).
  void Function() consumeContentFocusRequest,
  BuildContext Function() context,
  void Function() endLoadStatus,
  // TEMP(iptv): _landingCategory -> IptvFiltersSection.landingCategory (step 4).
  String? Function(String? orderKey, List<String> categories) landingCategory,
  Future<void> Function() loadFavorites,
  // TEMP(iptv): _loadProgress -> IptvVirtualResults.loadProgress (step 4).
  Future<void> Function(int ticket, List<IptvChannel> channels) loadProgress,
  DbChannelList Function(CatalogSnapshot snap, {String? group, String? search})
  makeDbList,
  bool Function() mounted,
  // TEMP(iptv): _recomputeSourceCounts -> IptvSourceCounts.recomputeSourceCounts (step 5).
  void Function() recomputeSourceCounts,
  StateSetter setState,
  // TEMP(iptv): _updateEpgContext -> IptvGuideContext.updateEpgContext (step 4).
  void Function(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket, {
    bool quiet,
  })
  updateEpgContext,
});

class IptvCatalogPresentation {
  final IptvCatalogPresentationDeps _deps;
  final IptvCatalogState _catalogState;

  IptvCatalogPresentation(this._deps) : _catalogState = _deps.catalogState;

  /// Bind a loaded catalog to the view: favorites migration, list swap,
  /// progress bars, warning surfacing, filters, EPG context. Shared by the
  /// network path and the stored-catalog path of [_loadPlaylist].
  /// [migrateFavorites] is false for snapshot/memory-cache passes — their
  /// URLs are not fresher than the favorites store's, so migrating against
  /// them is at best a no-op and at worst a backward walk.
  Future<void> presentCatalog(
    IptvPlaylist playlist,
    int ticket,
    IptvParseResult result, {
    bool migrateFavorites = true,
    String? cacheKey,
  }) async {
    // A parse worker that ingested into the catalog DB hands back a receipt
    // instead of rows — presentation then reads from the DB.
    final receipt = result.ingest;
    if (receipt != null) {
      final snap = IptvCatalogDb.snapshot(receipt.catalogKey);
      if (snap != null && snap.channelCount > 0) {
        await presentDbCatalog(
          playlist,
          ticket,
          snap,
          warning: result.warning,
          migrateFavorites: migrateFavorites,
        );
        return;
      }
    }
    // Virtual/local catalogs do not live in the SQL catalog. Give their live
    // rows a deterministic session number so every channel surface still has
    // a useful number; persisted network providers use the stable DB mapping.
    if (result.channels.any(
      (channel) => channel.isLive && channel.channelNumber == null,
    )) {
      final usedNumbers = <int>{
        for (final channel in result.channels)
          if (channel.isLive && channel.channelNumber != null)
            channel.channelNumber!,
      };
      var next = 0;
      int nextFreeNumber() {
        do {
          next++;
        } while (usedNumbers.contains(next));
        usedNumbers.add(next);
        return next;
      }

      result = IptvParseResult(
        channels: [
          for (final channel in result.channels)
            if (channel.isLive)
              IptvChannel(
                channelNumber: channel.channelNumber ?? nextFreeNumber(),
                name: channel.name,
                url: channel.url,
                logoUrl: channel.logoUrl,
                group: channel.group,
                duration: channel.duration,
                contentType: channel.contentType,
                attributes: channel.attributes,
                httpHeaders: channel.httpHeaders,
              )
            else
              channel,
        ],
        categories: result.categories,
        error: result.error,
        warning: result.warning,
        epgUrl: result.epgUrl,
      );
    }
    // Migrate list memberships saved under older URL formats (e.g. before the
    // Xtream /live/ URL fix) to the freshly fetched URLs, and backfill the
    // presentation metadata of rows carried over from the pre-v5 favorites
    // table, then reload so the stars line up. (A list shelf's channels ARE
    // the store — nothing to migrate against.)
    if (migrateFavorites &&
        !playlist.isFavorites &&
        !playlist.isCustomList &&
        !playlist.isContinueWatching) {
      await IptvFavoritesStorage.reconcileIptvFavoriteUrls(result.channels);
    }
    await _deps.loadFavorites();
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;

    // Focus nodes are created lazily per channel INSTANCE (identity-keyed,
    // never URL — duplicate URLs are legal and must not share a node) in the
    // grid's itemBuilder via _focusNodeFor.

    // Hidden-category rules apply on this materialized fallback too — for a
    // cacheable source it serves whenever the ingest didn't happen (database
    // unopenable, empty receipt, memory-cache hit), and presenting the raw
    // rows would bring every hidden category back for the session. [result]
    // itself stays unfiltered: the favorites reconcile above and the EPG
    // context below scan hidden rows in DB mode too.
    var channels = result.channels;
    if (playlist.isLocalFile) {
      channels = await IptvFavoritesStorage.applyIptvCategoryChannelOrders(
        playlist.id,
        channels,
      );
      if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    } else if (cacheKey != null) {
      channels = IptvCatalogDb.applyCategoryChannelOrders(cacheKey, channels);
    }
    var categories = result.categories;
    if (playlist.isLocalFile) {
      categories = await IptvCategoryOrder.applyStoredLocalCategoryOrder(
        playlist.id,
        categories,
      );
      if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
      _catalogState.hiddenCategories = const {};
    } else if (cacheKey == null) {
      // Virtual/addon sources have no durable order or hidden-category rules.
      _catalogState.hiddenCategories = const {};
    } else {
      categories = IptvCatalogDb.applyCategoryOrder(cacheKey, categories);
      categories = withoutHidden(cacheKey, categories);
      if (_catalogState.hiddenCategories.isNotEmpty) {
        channels = [
          for (final channel in channels)
            if (!_catalogState.hiddenCategories.contains(channel.group))
              channel,
        ];
      }
    }

    _deps.endLoadStatus();
    _deps.setState(() {
      _catalogState.isLoading = false;
      _catalogState.isLoadingMore = false;
      _catalogState.allChannels = channels;
      _catalogState.categories = categories;
      // The selected category can be one the hidden set just removed — fall
      // back to All rather than pinning the filter to a chip that no longer
      // exists (the DB path does the same).
      if (_catalogState.selectedCategory != null &&
          !categories.contains(_catalogState.selectedCategory)) {
        _catalogState.selectedCategory = null;
      }
      _catalogState.selectedCategory ??= _deps.landingCategory(
        playlist.isLocalFile
            ? IptvCatalogKey.forLocalCategoryOrder(playlist.id)
            : cacheKey,
        categories,
      );
      // Disarmed even when the seed declined (search active, keyless
      // source): only the load's first present gets the chance.
      _catalogState.landingSeedArmed = false;
      // This present is the materialized fallback — if a previous load left a
      // DB snapshot behind (e.g. the fresh fetch's receipt came back empty
      // while an older generation was still pinned), keeping it would split
      // the view's brain: _applyFilters would build facades over the dead
      // generation while _allChannels holds these rows, and every faulted row
      // would degrade to a placeholder.
      _catalogState.dbSnapshot = null;
      _catalogState.dbGroupCounts = const {};
    });

    // After the rows exist, not before: _loadProgress setStates too, and
    // running it first would paint one extra frame against an empty list.
    // The bars simply appear a frame later.
    await _deps.loadProgress(ticket, channels);
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;

    // Surface non-fatal degradation (e.g. categories unavailable) so missing
    // groups don't look like deleted channels.
    if (result.warning != null) {
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text(result.warning!)));
    }

    _deps.applyFilters();
    // Kept for settings round-trips: an EPG-URL edit re-runs the guide
    // context against this result without refetching the whole playlist.
    _catalogState.lastLoadResult = result;
    _deps.updateEpgContext(playlist, result, ticket);
    _deps.consumeContentFocusRequest();
  }

  /// Bind a DB-backed catalog to the view: [allChannels] and
  /// [filteredChannels] become [DbChannelList] facades that page from SQL.
  /// The DB-mode counterpart of [_presentCatalog]'s list swap.
  Future<void> presentDbCatalog(
    IptvPlaylist playlist,
    int ticket,
    CatalogSnapshot snap, {
    String? warning,
    bool migrateFavorites = false,
  }) async {
    if (migrateFavorites) {
      // Worker-side scan against the catalog rows — never a facade walk on
      // this isolate.
      await IptvFavoritesStorage.reconcileIptvFavoriteUrlsForCatalog(
        snap.catalogKey,
      );
    }
    await _deps.loadFavorites();
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;

    // Off-isolate: this GROUP BY scans the whole generation, synchronously
    // ran in exactly the turn that builds the first frame.
    final groups = await IptvCatalogDb.groupsAsync(snap);
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    // Provider category list when the panel served one (its order is the
    // chips' order today); groups derived from the rows otherwise (M3U).
    final categories = deriveCategories(snap, groups);
    final counts = <String, int>{
      for (final g in groups)
        if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
    };

    _deps.endLoadStatus();
    _deps.setState(() {
      _catalogState.isLoading = false;
      _catalogState.isLoadingMore = false;
      _catalogState.dbSnapshot = snap;
      _catalogState.dbGroupCounts = counts;
      _catalogState.allChannels = _deps.makeDbList(snap);
      _catalogState.categories = categories;
      if (_catalogState.selectedCategory != null &&
          !categories.contains(_catalogState.selectedCategory)) {
        _catalogState.selectedCategory = null;
      }
      _catalogState.selectedCategory ??= _deps.landingCategory(
        snap.catalogKey,
        categories,
      );
      _catalogState.landingSeedArmed = false;
    });

    if (warning != null && _deps.mounted()) {
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text(warning)));
    }

    _deps.applyFilters();
    final displayed = IptvParseResult(
      channels: _catalogState.allChannels,
      categories: categories,
      epgUrl: snap.epgUrl,
    );
    _catalogState.lastLoadResult = displayed;
    _deps.updateEpgContext(playlist, displayed, ticket);
    _deps.consumeContentFocusRequest();
    // A first-time source reaches here via a blocking ingest with NO success
    // chip — the rail count for it must not wait for a later refresh.
    _deps.recomputeSourceCounts();
  }

  /// [categories] with the user's hidden ones removed — and, as a side
  /// effect, [hiddenCategories] re-read for [catalogKey]. The ONE place the
  /// list-filtering semantics live: the DB present/revalidate sites (via
  /// [_deriveCategories]), the materialized fallback and the in-player picker
  /// all route through it, so a change here can't split them.
  List<String> withoutHidden(String catalogKey, List<String> categories) {
    _catalogState.hiddenCategories = IptvCatalogDb.hiddenGroups(catalogKey);
    if (_catalogState.hiddenCategories.isEmpty) return categories;
    return [
      for (final c in categories)
        if (!_catalogState.hiddenCategories.contains(c)) c,
    ];
  }

  /// The category list the chips/dropdown show, with the user's hidden
  /// categories removed — and, as a side effect, [hiddenCategories] brought
  /// up to date for [snap].
  ///
  /// [groups] comes from a query that already excludes hidden rows, so the
  /// M3U path (categories derived from the rows) needs no filtering; only the
  /// provider's verbatim list does. Both paths are here so every present /
  /// revalidate site derives the list the same way.
  List<String> deriveCategories(
    CatalogSnapshot snap,
    List<CatalogGroup> groups,
  ) {
    final categories = withoutHidden(snap.catalogKey, snap.categories);
    if (snap.categories.isEmpty) {
      return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, [
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!,
      ]);
    }
    return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, categories);
  }
}
