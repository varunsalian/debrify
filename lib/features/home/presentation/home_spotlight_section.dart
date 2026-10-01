import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/home_collection_rows.dart';
import '../../../models/home_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/platform_util.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../data/home_catalog_repository.dart';
import '../models/home_catalog_search_status.dart';

typedef HomeSpotlightDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeHeroSource Function() heroSource,
  List<CatalogSection> Function() sections,
  HomeCatalogRepository Function() repository,
  Future<void> Function(List<StremioMeta>, {String? sourceTitle})
  publishTopShelf,
});

/// Spotlight's independent hero-source request lifetime and reel selection.
class HomeSpotlightSection {
  HomeSpotlightSection(this._deps, this._catalogSection);
  final HomeSpotlightDeps _deps;
  final HomeCatalogSearchStatus _catalogSection;

  final GlobalKey<SpotlightBoardState> spotlightKey =
      GlobalKey<SpotlightBoardState>();
  final FocusNode spotlightHeroNode = FocusNode(debugLabel: 'spotlight-hero');

  /// The hero reel fetched from the user's chosen source (`random`/`custom`
  /// modes), fetched by [resolveSpotlightHeroSource] independently of the
  /// board batches — the chosen catalog may sit pages down the board, or be
  /// hidden as a row entirely. Null in `auto` mode, while the fetch is in
  /// flight, and when every candidate came up dead — all of which fall back
  /// to the first non-empty board row below.
  CatalogSection? spotlightHeroOverride;

  /// Guards [resolveSpotlightHeroSource] against overlapping runs (a Home
  /// Rows save landing mid-load): only the newest run may commit.
  int heroSourceResolveGen = 0;
  bool heroSourceResolving = false;
  // The presentation deadline can expire while the underlying request is
  // still pending. A return snapshot must resume that request too.
  bool heroSourceResolutionPending = false;
  bool spotlightEntryRevealed = false;

  /// Fetch the hero reel for the current [_deps.heroSource()] pref.
  ///
  /// Candidates come from the FULL browsable set, not [_boardRefs] — hiding a
  /// catalog's row on the board must not blank a hero pinned to that same
  /// catalog. Candidates are shuffled so `random` mode and a multi-pick
  /// `custom` re-roll on every board load; the first candidate that returns
  /// items wins. Attempts are capped so a wall of dead catalogs can't fan out
  /// unbounded fetches; exhausting the cap (or the candidates) clears the
  /// override, which IS the auto fallback.
  Future<void> resolveSpotlightHeroSource(List<StremioAddon> addons) async {
    final gen = ++heroSourceResolveGen;
    heroSourceResolving = true;
    heroSourceResolutionPending = true;
    try {
      // The initial presentation must not wait forever on a dead hero source.
      // A late result may still populate the reel after the cards fallback.
      await fetchSpotlightHeroSource(addons, gen)
          .whenComplete(() {
            if (_deps.mounted() && gen == heroSourceResolveGen) {
              heroSourceResolutionPending = false;
            }
          })
          .timeout(const Duration(seconds: 25), onTimeout: () {});
    } finally {
      if (_deps.mounted() && gen == heroSourceResolveGen) {
        _deps.setState(() => heroSourceResolving = false);
      }
    }
  }

  Future<void> fetchSpotlightHeroSource(
    List<StremioAddon> addons,
    int gen,
  ) async {
    final source = _deps.heroSource();
    if (source.mode != HomeHeroSourceMode.auto) {
      final all = [
        for (final a in addons)
          for (final c in a.catalogs)
            if (c.isBrowsable) (a, c),
      ];
      final List<(StremioAddon, StremioAddonCatalog)> candidates;
      if (source.mode == HomeHeroSourceMode.random) {
        // Random draws TITLES only. Live catalogs — 'tv' is what the
        // Stremio-IPTV service itself keys on, 'channel'/'radio' are the
        // spec's other live-ish types — serve channel logos as their art, so
        // the reel cover-crops a wordmark to a full screen (TvVoo's logo,
        // full-bleed, was the report). An EXPLICIT custom pick of such a
        // catalog is left alone: choosing it by name is a deliberate act.
        const live = {'tv', 'channel', 'radio'};
        candidates = [
          for (final ref in all)
            if (!live.contains(ref.$2.type.toLowerCase())) ref,
        ];
      } else {
        // Stored picks that no longer resolve (addon uninstalled, catalog
        // gone from its manifest) simply drop out; they are NOT removed from
        // the pref, so reinstalling the addon brings the pick back.
        final byId = {
          for (final (a, c) in all) '${a.id}:${c.type}:${c.id}': (a, c),
        };
        candidates = [
          for (final id in source.ids)
            if (byId.containsKey(id)) byId[id]!,
        ];
      }
      candidates.shuffle(Random());
      const maxAttempts = 8;
      var attempts = 0;
      for (final (addon, catalog) in candidates) {
        if (attempts++ >= maxAttempts) break;
        if (!_deps.mounted() || gen != heroSourceResolveGen) return;
        try {
          final page = await _deps.repository().fetchHeroPage(addon, catalog);
          if (!_deps.mounted() || gen != heroSourceResolveGen) return;
          if (page.items.isEmpty) continue;
          _deps.setState(() {
            spotlightHeroOverride = CatalogSection(
              title: CatalogSection.rowTitle(catalog),
              addon: addon,
              catalog: catalog,
              items: page.items.toList(),
              nextSkip: page.nextSkip,
            );
          });
          publishTopShelfSpotlight();
          return;
        } catch (_) {
          // Dead addon or catalog — try the next candidate.
        }
      }
    }
    // Auto mode, no usable candidate, or every attempt failed — drop any
    // stale override so the reel falls back rather than pinning old prefs.
    if (!_deps.mounted() || gen != heroSourceResolveGen) return;
    if (spotlightHeroOverride != null) {
      _deps.setState(() => spotlightHeroOverride = null);
    }
    publishTopShelfSpotlight();
  }

  /// The hero reel.
  ///
  /// NOT `_stageRailsSection.stageRails[0]`: the user's first row may be a channel, playlist, or
  /// Continue Watching rail rather than a catalog, and rails can arrive as
  /// tracker data lands. The hero needs a
  /// stable list of real catalog titles, so it takes the user's resolved
  /// source pick when there is one, else the first section that has any items
  /// — and caps it either way: a reel longer than about eight is a list, not
  /// a hero.
  CatalogSection? get spotlightHeroSection {
    // A catalog search swaps `_deps.sections()` to results, and the reel follows
    // them — the pinned source is Home-board furniture and must not paint
    // over a search.
    final override = spotlightHeroOverride;
    if (override != null &&
        _catalogSection.catalogQuery.isEmpty &&
        !_catalogSection.catalogSearching) {
      return override;
    }
    for (final section in _deps.sections()) {
      // Folder tiles aren't titles, so they can't feed the hero reel.
      if (section is HomeCollectionSection) continue;
      if (section.items.isNotEmpty) return section;
    }
    return null;
  }

  List<StremioMeta> get spotlightHero =>
      spotlightHeroSection?.items.take(8).toList() ?? const [];

  void publishTopShelfSpotlight() {
    if (!PlatformUtil.isTvOS || _deps.searchMode() || _deps.discoverMode()) {
      return;
    }
    unawaited(
      _deps.publishTopShelf(
        spotlightHero,
        sourceTitle: spotlightHeroSection?.title,
      ),
    );
  }
}
