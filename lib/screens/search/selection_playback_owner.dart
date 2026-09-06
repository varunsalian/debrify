import 'package:flutter/material.dart';

import '../../models/advanced_search_selection.dart';
import '../../models/play_loader_art.dart';
import '../../models/stremio_addon.dart';
import '../../services/torrent_playback_service.dart';
import '../../utils/tv_keys.dart';
import 'search_sources.dart' show buildSearchSources;

/// Explicit live routing/refresh dependencies; no host State or stored context.
class SelectionPlaybackRoutes {
  const SelectionPlaybackRoutes({
    required this.readIsTelevision,
    required this.refreshBoundSources,
    required this.refreshAfterPlayback,
  });

  final bool Function() readIsTelevision;
  final Future<void> Function() refreshBoundSources;
  final Future<void> Function() refreshAfterPlayback;
}

/// Owns selection metadata, loader art, service launch and Sources routing.
/// The host retains entry guards and the per-call external listener lifecycle.
class SelectionPlaybackOwner {
  String? activeAddonId;
  PlayLoaderArt? get pendingArt => _pendingPlayArt;

  PlaybackMeta metaFor(AdvancedSearchSelection sel) => PlaybackMeta.catalog(
    // Only a real IMDb id here — the launcher's Trakt auto-sync + local
    // Continue Watching must never fire on an empty or non-IMDb (IPTV) id,
    // even though the search itself still uses sel.imdbId (the addon id).
    imdbId: sel.imdbId.startsWith('tt') ? sel.imdbId : null,
    contentType: sel.contentType ?? (sel.isSeries ? 'series' : 'movie'),
    season: sel.season,
    episode: sel.episode,
    title: sel.title,
    posterUrl: sel.posterUrl,
    year: sel.year,
    addonId: activeAddonId,
    traktProgressPercent: sel.traktProgressPercent,
    // Trakt-row plays scrobble to Trakt instead of saving a duplicate local
    // Continue Watching entry (mirrors Home passing selection.traktSource).
    traktScrobble: sel.traktSource,
    simklProgressPercent: sel.simklProgressPercent,
    simklScrobble: sel.simklSource,
    mdblistProgressPercent: sel.mdblistProgressPercent,
    mdblistScrobble: sel.mdblistSource,
    art: _artFor(sel.imdbId, sel.title),
  );

  /// Loader artwork for the title being played, captured by the catalog play entry point
  /// from the catalog meta it already holds. Presentation only.
  ///
  /// Keyed, because plays reach [metaFor] through selections this screen did
  /// not build (tracker continue-watching rows, the episode picker) — an
  /// unkeyed stash would paint the previous title's backdrop behind the next
  /// play. A miss simply means no art, which the loader already handles.
  PlayLoaderArt? _pendingPlayArt;
  String? _pendingPlayArtKey;

  void captureCatalogArt(StremioMeta item) {
    final key = _playArtKey(item.effectiveImdbId ?? item.id, item.name);
    // The detail page publishes a strictly richer version of the same title
    // (logo, runtime, rating, certificate — none of which catalog rows carry),
    // so never let the row's sparse copy overwrite it.
    if (_pendingPlayArt != null && _pendingPlayArtKey == key) return;
    final art = PlayLoaderArt.fromMeta(item);
    if (art.isEmpty) {
      _pendingPlayArt = null;
      _pendingPlayArtKey = null;
      return;
    }
    _pendingPlayArt = art;
    _pendingPlayArtKey = key;
  }

  /// The detail page's enrichment, replacing whatever the row had.
  void adoptDetailArt(StremioMeta item, PlayLoaderArt art) {
    _pendingPlayArt = art;
    _pendingPlayArtKey = _playArtKey(
      item.effectiveImdbId ?? item.id,
      item.name,
    );
  }

  static String _playArtKey(String? id, String title) =>
      '${id ?? ''}|${title.trim().toLowerCase()}';

  PlayLoaderArt? _artFor(String? id, String title) {
    final art = _pendingPlayArt;
    if (art == null) return null;
    // Either half matching is enough: tracker rows carry the IMDb id but often
    // a differently-punctuated title, and id-less addon titles carry neither.
    final key = _playArtKey(id, title);
    if (key == _pendingPlayArtKey) return art;
    final storedId = _pendingPlayArtKey?.split('|').first ?? '';
    if (storedId.isNotEmpty && id == storedId) return art;
    return null;
  }

  /// Return the service Future itself: the host's try/await/finally owns it.
  Future<void> launch(
    BuildContext context,
    AdvancedSearchSelection sel, {
    required SelectionPlaybackRoutes routes,
  }) => TorrentPlaybackService.playFromSelection(
    context,
    imdbId: sel.imdbId,
    isMovie: !sel.isSeries,
    season: sel.season,
    episode: sel.episode,
    meta: metaFor(sel),
    // Only the play handoff logs here. Ordinary browse is logged by the host
    // before its empty-ID guard and before evaluating State.context.
    openSourcePicker: () {
      debugPrint(
        '[SeriesResume] picker-open title="${sel.title}" id=${sel.imdbId} '
        'target=S${sel.season}E${sel.episode} label="${sel.formattedLabel}"',
      );
      browse(context, sel, routes: routes, forcePlayOnTap: true);
    },
  );

  /// Called only after the host's original State.mounted guard. Do the route
  /// lookup even for external launches, before evaluating the branch.
  Future<void> refreshAfterLaunch(
    BuildContext context, {
    required bool external,
    required SelectionPlaybackRoutes routes,
  }) {
    final boardOnTop = ModalRoute.of(context)?.isCurrent ?? false;
    if (external || !boardOnTop) {
      return routes.refreshBoundSources();
    }
    return routes.refreshAfterPlayback();
  }

  /// Host browse guards empty IDs before reading State.context; the service
  /// also rejects empty IDs before invoking its play-button picker callback.
  /// Neither path logs twice. Metadata and television remain builder-time reads.
  void browse(
    BuildContext context,
    AdvancedSearchSelection sel, {
    required SelectionPlaybackRoutes routes,
    bool forcePlayOnTap = false,
  }) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TvHeldKeyGuard(
              child: buildSearchSources(
                selection: sel,
                meta: metaFor(sel),
                isTelevision: routes.readIsTelevision(),
                forcePlayOnTap: forcePlayOnTap,
              ),
            ),
          ),
        )
        // Deliberately unguarded, as on the original host route.
        .then((_) => routes.refreshAfterPlayback());
  }
}
