import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/iptv_cw_entry.dart';
import '../data/home_catalog_origin_repository.dart';
import 'home_continuation_section.dart';
import 'home_playback_navigation.dart';
import 'home_catalog_actions.dart';
import 'home_item_actions.dart';

typedef HomeContinuationPlaybackDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  StremioAddon Function(String?) addonForContinue,
  String? Function(StremioMeta) imdbOf,
  VoidCallback markPlaybackStarted,
  Future<void> Function() refreshAfterPlayback,
  Future<void> Function(BuildContext, IptvCwEntry, {required bool isTelevision})
  openIptv,
});

/// Opens and resumes continuation titles through the existing catalog and IPTV paths.
class HomeContinuationPlayback {
  HomeContinuationPlayback(
    this._deps,
    this._section,
    this._playback,
    this._catalog,
    this._items,
  );
  final HomeContinuationPlaybackDeps _deps;
  final HomeContinuationSection _section;
  final HomePlaybackNavigation _playback;
  final HomeCatalogActions _catalog;
  final HomeItemActions _items;

  /// Open an IPTV Continue Watching card: a series routes to the merged Xtream
  /// series page, a movie resumes playback. Both go through [IptvCwRouter];
  /// [_playedSinceRefresh] latches so the return refresh rebuilds the shelves.
  Future<void> openIptvCwItem(StremioMeta item) async {
    final entry = _section.iptvCwByKey[item.id];
    if (entry == null) return;
    final context = _deps.context();
    _deps.markPlaybackStarted();
    await _deps.openIptv(context, entry, isTelevision: _deps.isTelevision());
    if (!context.mounted) return;
    // Off-TV push() awaits to the pop; on TV the native-return hook
    // ([_onPlaybackReturned]) refreshes. Refresh here too for the in-app path
    // (series detail / in-app player) so a resumed position updates the shelf.
    await _deps.refreshAfterPlayback();
  }

  /// Open a Continue Watching title as a normal detail page (no Home-style
  /// list menu). The detail's action row + a "Remove from Continue Watching"
  /// action are wired via [_items.openItem] (which detects membership in [_section.cwIds]).
  void openContinueItem(StremioMeta item) {
    _items.openItem(
      item,
      item.sourceAddon ??
          _deps.addonForContinue(_section.cwAddonId[item.imdbId]),
    );
  }

  /// Long-press quick-play for a Continue Watching title — resumes directly
  /// (series resume the last-played episode) without opening the detail.
  void onContinuePlay(StremioMeta item) {
    _catalog.onCatalogPlay(
      item,
      item.sourceAddon ??
          _deps.addonForContinue(_section.cwAddonId[item.imdbId]),
    );
  }

  /// Open a plain Simkl-list title (Discover's Simkl Trending/watchlist lists) —
  /// a normal catalog detail, no resume. The CW list uses [openSimklCwItem]
  /// instead, so a title browsed fresh here never opens mid-episode.
  void openSimklItem(StremioMeta item, {String? heroTag}) {
    _items.openItem(
      item,
      HomeCatalogOriginRepository.addonForItem(item),
      heroTag: heroTag,
    );
  }

  /// Quick-play a plain Simkl-list title like any other catalog item (no
  /// resume). The CW list uses [playSimklCwItem].
  void playSimklItem(StremioMeta item) {
    _catalog.onCatalogPlay(
      item,
      HomeCatalogOriginRepository.addonForItem(item),
    );
  }

  // ── Trakt Continue Watching ───────────────────────────────────────────────

  /// Open a Trakt Continue Watching title as a normal detail page.
  void openTraktItem(StremioMeta item) {
    _items.openItem(
      item,
      _deps.addonForContinue(item.sourceAddon?.id),
      isTraktSource: true,
    );
  }

  /// Resume a Trakt Continue Watching title — resolves the paused/next episode
  /// (an extra Trakt call for series) and plays.
  Future<void> playTraktItem(StremioMeta item) async {
    if (!_playback.catalogNavigationCurrent()) return;
    final cwItem = _section.traktByImdb[_deps.imdbOf(item)];
    if (cwItem == null) {
      // Not in Continue Watching — a fetched Trakt list title (Trending,
      // Watchlist, …). Play it like a catalog title: addon-stream resolution
      // with the same Trakt-first resume the detail page's Play button uses.
      await _catalog.onCatalogPlay(
        item,
        _deps.addonForContinue(item.sourceAddon?.id),
        isTraktSource: true,
        preferTraktResume: true,
      );
      return;
    }
    final resume = await _catalog.seriesResumeRepository.traktSelection(
      item,
      cached: cwItem,
      isCurrent: _playback.catalogNavigationCurrent,
    );
    if (!_playback.catalogNavigationCurrent()) return;
    final sel = resume?.sel;
    if (sel == null) {
      _playback.snack("Couldn't resolve where to resume \"${item.name}\".");
      return;
    }
    _playback.playSelection(sel);
  }

  /// Open a Simkl Continue Watching title as a detail page. For a series, scroll
  /// the episodes panel to the paused episode (the same path the Calendar uses);
  /// resume itself is handled by the detail's three-way resume when Simkl is
  /// connected. No `isTraktSource` flag — this is a plain, source-neutral open.
  void openSimklCwItem(StremioMeta item) {
    final cw = _section.simklByImdb[_section.simklCardKey(item)];
    _items.openItem(
      item,
      HomeCatalogOriginRepository.addonForItem(item),
      initialSeason: (cw != null && !cw.isMovie) ? cw.season : null,
      initialEpisode: (cw != null && !cw.isMovie) ? cw.episode : null,
    );
  }

  /// Resume a Simkl Continue Watching title directly (quick-play): builds a
  /// selection carrying the paused season/episode + Simkl progress percent and
  /// plays it, mirroring the Trakt quick-play.
  Future<void> playSimklCwItem(StremioMeta item) async {
    if (!_playback.catalogNavigationCurrent()) return;
    _playback.activeAddonId = HomeCatalogOriginRepository.addonForItem(item).id;
    _playback.playbackArtwork.capture(item);
    final cw = _section.simklByImdb[_section.simklCardKey(item)];
    if (cw == null) {
      // Not in the CW map (a See-All grid title that fell out of the list) —
      // play it like a plain catalog title; three-way resume still applies.
      await _catalog.onCatalogPlay(
        item,
        HomeCatalogOriginRepository.addonForItem(item),
      );
      return;
    }
    _playback.playSelection(cw.selection);
  }

  void openMdblistCwItem(StremioMeta item) {
    final cw = _section.mdblistByImdb[_deps.imdbOf(item)];
    _items.openItem(
      item,
      _deps.addonForContinue(item.sourceAddon?.id),
      initialSeason: cw?.selection.season,
      initialEpisode: cw?.selection.episode,
      isMdblistSource: true,
    );
  }

  Future<void> playMdblistCwItem(StremioMeta item) async {
    if (!_playback.catalogNavigationCurrent()) return;
    final cw = _section.mdblistByImdb[_deps.imdbOf(item)];
    if (cw == null) {
      await _catalog.onCatalogPlay(
        item,
        _deps.addonForContinue(item.sourceAddon?.id),
        isMdblistSource: true,
      );
      return;
    }
    _playback.playSelection(cw.selection);
  }
}
