import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/playback_meta.dart';
import '../../../screens/episodes_screen.dart';
import '../data/home_catalog_playback_payload.dart';
import 'home_catalog_playback_bridge.dart';
import 'home_sources_navigation.dart';
import 'home_playback_artwork.dart';

typedef HomePlaybackNavigationDeps = ({
  bool Function() mounted,
  bool Function() profileCurrent,
  BuildContext Function() context,
  bool Function() isTelevision,
  VoidCallback clearResume,
  Future<void> Function() refreshBoundSources,
  Future<void> Function({bool trackers}) refreshAfterPlayback,
  String? Function(StremioMeta) imdbOf,
  int Function(StremioMeta) boundCountFor,
  Future<void> Function(StremioMeta, {bool Function()? isCurrent}) editSource,
  // Resolved per navigation, as the provider read was.
  HomeSourcesNavigation Function() sources,
});

/// Owns playback metadata and selection/episode/source navigation for this route.
class HomePlaybackNavigation {
  HomePlaybackNavigation(this._ref, this._deps);
  final WidgetRef _ref;
  final HomePlaybackNavigationDeps _deps;

  /// The addon that produced the item currently being played/browsed, threaded
  /// into playback so Continue Watching can route resume / next-episode back to
  /// it (matching Home's `addonId`). Set whenever we open a catalog item.
  String? activeAddonId;

  void onCatalogBrowse(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    if (item.type == 'series') {
      openEpisodes(
        item,
        addon,
        isTraktSource: isTraktSource,
        isMdblistSource: isMdblistSource,
      );
    } else {
      browseSelection(
        homeCatalogMovieSelection(
          item,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        ),
        metadataAddonId: addon.id,
        catalogItem: item.withSourceAddon(addon),
      );
    }
  }

  void openEpisodes(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    final context = _deps.context();
    activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kEpisodesRouteName),
            builder: (_) => EpisodesScreen(
              show: item,
              addon: addon,
              isTelevision: _deps.isTelevision(),
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
              // EpisodesScreen pops itself (and the detail route) before firing
              // these, so we're back on the Search screen when they run.
              onQuickPlay: (selection) => playSelection(
                selection,
                metadataAddonId: addon.id,
                catalogItem: item.withSourceAddon(addon),
              ),
              onItemSelected: (selection) => browseSelection(
                selection,
                metadataAddonId: addon.id,
                catalogItem: item.withSourceAddon(addon),
              ),
              // "Select Source" button: manage/pin sources via the same picker
              // the detail screen uses (edit dialog when already bound, else the
              // Torrent Search / Local / RD / TorBox picker) for a consistent
              // entry point.
              boundSourceCount: _deps.boundCountFor,
              onSelectSource: (show) {
                activeAddonId = addon.id;
                return _deps.editSource(show.withSourceAddon(addon));
              },
            ),
          ),
        )
        .then((_) {
          // EpisodesScreen can mark watched / play; its plays route through
          // playSelection (which clears too), but marks don't — never let a
          // pre-visit reconciled answer survive the trip.
          _deps.clearResume();
          _deps.refreshBoundSources();
        });
  }

  /// Binding payloads and keyword seeds belong to the Sources presentation bridge.
  void openSourceBinding(
    StremioMeta item, {
    bool keyword = false,
    bool Function()? isCurrent,
  }) {
    bool current() => catalogNavigationCurrent() && (isCurrent?.call() ?? true);
    if (!current()) return;
    final context = _deps.context();
    unawaited(
      _deps.sources().bindCatalog(
        context,
        item: item,
        progressId: _deps.imdbOf(item),
        keyword: keyword,
        buildMeta: (selection) => metaFor(selection, catalogItem: item),
        isTelevision: () => _deps.isTelevision(),
        isCurrent: current,
        onReturned: _deps.refreshBoundSources,
      ),
    );
  }

  PlaybackMeta metaFor(
    AdvancedSearchSelection sel, {
    String? addonId,
    StremioMeta? catalogItem,
  }) => homeCatalogPlaybackMeta(
    sel,
    addonId: addonId,
    fallbackAddonId: activeAddonId,
    catalogItem: catalogItem,
    art: playbackArtwork.forSelection(sel.imdbId, sel.title),
  );

  final HomePlaybackArtwork playbackArtwork = HomePlaybackArtwork();

  /// Catalog auto-best play — the service picks the provider, shows the real
  /// cinematic overlay, searches, and plays (with source list + content
  /// metadata so the in-player Sources switcher + Continue Watching work).
  Future<void> playSelection(
    AdvancedSearchSelection sel, {
    String? metadataAddonId,
    StremioMeta? catalogItem,
  }) async {
    bool current() => _deps.mounted() && _deps.profileCurrent();
    if (!current()) return;
    final context = _deps.context();
    // Capture the originating detail's provider for delayed Sources handoffs.
    final addonId = metadataAddonId ?? activeAddonId;
    // No pre-playback reconciled answer may survive into post-playback reads.
    _deps.clearResume();
    await _ref
        .read(homeCatalogPlaybackBridgeProvider)
        .play(
          context,
          selection: sel,
          buildMeta: () =>
              metaFor(sel, addonId: addonId, catalogItem: catalogItem),
          // Honor "Play button opens" for this exact episode. A manual source tap
          // must play directly rather than asking the user's intent a second time.
          openSourcePicker: () => browseSelection(
            sel,
            forcePlayOnTap: true,
            metadataAddonId: addonId,
            catalogItem: catalogItem,
          ),
          isCurrent: current,
          refreshBoundSources: _deps.refreshBoundSources,
          refreshAfterPlayback: _deps.refreshAfterPlayback,
        );
  }

  bool catalogNavigationCurrent() => _deps.mounted() && _deps.profileCurrent();

  /// Manual sources list in-tab — the screen searches itself (own loading) and
  /// each tap plays with the full source list + content metadata.
  void browseSelection(
    AdvancedSearchSelection sel, {
    // Play has already expressed intent; manual Sources keeps the usual prompt.
    bool forcePlayOnTap = false,
    String? metadataAddonId,
    StremioMeta? catalogItem,
  }) {
    if (!catalogNavigationCurrent()) return;
    final context = _deps.context();
    unawaited(
      _deps.sources().browse(
        context,
        selection: sel,
        buildMeta: () =>
            metaFor(sel, addonId: metadataAddonId, catalogItem: catalogItem),
        isTelevision: () => _deps.isTelevision(),
        forcePlayOnTap: forcePlayOnTap,
        isCurrent: catalogNavigationCurrent,
        onReturned: _deps.refreshAfterPlayback,
      ),
    );
  }

  void snack(String message) {
    if (!_deps.mounted()) return;
    final context = _deps.context();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}
