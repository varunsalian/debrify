import 'dart:async';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:flutter/material.dart';

class EpisodesPanelEnrichment {
  final EpisodesPanelDeps _deps;
  EpisodesPanelEnrichment(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelResources get _r => _deps.parts.resources;
  EpisodesPanelServices get _sv => _deps.parts.services;
  bool get mounted => _deps.mounted();

  /// Backfill per-episode ratings from Trakt's public seasons API, keyed off
  /// the show's IMDb id. Runs only when NO episode already has a real rating —
  /// i.e. an addon like Cinemeta returned `rating: 0` for everything. This is
  /// exactly the rating source the Trakt fallback path uses, applied on top of
  /// the addon's richer metadata (thumbnails, overviews, air dates). Best-effort
  /// and non-blocking: any failure just leaves ratings unshown.
  Future<void> enrichEpisodeRatings(
    StremioMeta show,
    List<TraktSeason> seasons,
    int generation,
  ) async {
    // Nothing to do if the episodes already carry real ratings.
    final hasRealRating = seasons.any(
      (s) => s.episodes.any((e) => (e.rating ?? 0) > 0),
    );
    if (hasRealRating) return;

    final imdbId = show.progressId ?? show.id;
    if (!MediaIdentity.isImdb(imdbId)) return;

    try {
      final raw = await _sv.traktService.fetchShowSeasons(imdbId);
      if (!mounted || generation != _s.episodeModeGeneration) return;

      // Build lookup: "S-E" → rating (only real, >0 ratings).
      final ratingMap = <String, double>{};
      for (final s in raw.map((s) => TraktSeason.fromJson(s))) {
        for (final e in s.episodes) {
          final r = e.rating;
          if (r != null && r > 0) ratingMap['${e.season}-${e.number}'] = r;
        }
      }
      if (ratingMap.isEmpty) return;

      var changed = false;
      for (final season in seasons) {
        for (final episode in season.episodes) {
          if ((episode.rating ?? 0) > 0) continue;
          final r = ratingMap['${episode.season}-${episode.number}'];
          if (r != null) {
            episode.rating = r;
            changed = true;
          }
        }
      }

      if (changed && mounted && generation == _s.episodeModeGeneration) {
        _deps.setState(() {});
        unawaited(_deps.parts.metadata.loadSelectedEpisodeMetadata());
      }
    } catch (e) {
      debugPrint('EpisodesPanel: Trakt rating enrichment failed: $e');
    }
  }

  /// Fetch the TVMaze `"S-E"` → still-URL map for [imdbId]. Never throws —
  /// resolves to null when TVMaze doesn't know the show or the fetch fails,
  /// so it's safe to fire-and-forget before its consumer exists.
  Future<Map<String, String>?> fetchTvmazeThumbMap(String? imdbId) async {
    if (imdbId == null) return null;
    try {
      final showData = await TVMazeService.lookupByImdbId(imdbId);
      final tvmazeId = showData?['id'] as int?;
      if (tvmazeId == null) return null;

      final tvmazeEpisodes = await TVMazeService.getEpisodes(tvmazeId);
      if (tvmazeEpisodes.isEmpty) return null;

      final imageMap = <String, String>{};
      for (final ep in tvmazeEpisodes) {
        final s = ep['season'] as int?;
        final e = ep['number'] as int?;
        final image = ep['image'] as Map<String, dynamic>?;
        final url =
            image?['medium'] as String? ?? image?['original'] as String?;
        if (s != null && e != null && url != null) {
          imageMap['$s-$e'] = url;
        }
      }
      return imageMap.isEmpty ? null : imageMap;
    } catch (e) {
      debugPrint('EpisodesPanel: TVMaze thumbnail fetch failed: $e');
      return null;
    }
  }

  /// Fill in per-episode thumbnails from TVMaze, keyed off the show's IMDb id.
  ///
  /// Only episodes that arrived without a thumbnail are touched, so addon
  /// meta-provided stills are preserved and Trakt-sourced episodes (which have
  /// none) get filled. Best-effort: any failure leaves the show-poster
  /// fallback in place. [prefetched] is the map fired alongside the seasons
  /// fetch on the Trakt path; when absent (addon path that still came up
  /// short) the fetch happens here.
  Future<void> enrichEpisodeThumbnails(
    StremioMeta show,
    List<TraktSeason> seasons,
    int generation, {
    Future<Map<String, String>?>? prefetched,
  }) async {
    // Nothing to do if every episode already has a thumbnail (addon path).
    final needsThumbnails = seasons.any(
      (s) => s.episodes.any(
        (e) => e.thumbnailUrl == null || e.thumbnailUrl!.isEmpty,
      ),
    );
    if (!needsThumbnails) return;

    final imageMap =
        await (prefetched ?? fetchTvmazeThumbMap(show.effectiveImdbId));
    if (imageMap == null) return;
    if (!mounted || generation != _s.episodeModeGeneration) return;

    var changed = false;
    for (final season in seasons) {
      for (final episode in season.episodes) {
        if (episode.thumbnailUrl != null && episode.thumbnailUrl!.isNotEmpty) {
          continue;
        }
        final url = imageMap['${episode.season}-${episode.number}'];
        if (url != null) {
          episode.thumbnailUrl = url;
          changed = true;
        }
      }
    }

    if (changed) {
      _deps.setState(() {});
      unawaited(_deps.parts.metadata.loadSelectedEpisodeMetadata());
    }
  }

  /// Robustly brings episode [epIndex] into view.
  ///
  /// The episode list is a lazy ListView with variable-height tiles, so a
  /// single fixed/proportional jump is unreliable — an off-screen target
  /// tile isn't built, leaving its FocusNode contextless. This re-reads
  /// scroll metrics each frame and converges (the builder's maxScrollExtent
  /// grows as more rows lay out). Once the tile exists: on TV focus it (the
  /// tile self-centers via EpisodeTile.onFocusChange and shows the focus
  /// border for the remote); on mobile/desktop just scroll it into view
  /// without focusing — an auto-applied golden focus border there looks out
  /// of place. Bounded so it can never spin.
  void scrollFocusEpisode(int epIndex, int episodeCount, int generation) {
    const int maxAttempts = 16;
    void attempt(int n) {
      if (!mounted || generation != _s.episodeModeGeneration) return;
      if (epIndex < 0 || epIndex >= _r.episodeFocusNodes.length) return;
      final node = _r.episodeFocusNodes[epIndex];
      // Once a tile has been built and scrolled back out, the node keeps a
      // stale context; treating that as "present" would stop converging and
      // focus/scroll a defunct element.
      if (detailNodeMounted(node)) {
        if (_deps.isTelevision()) {
          node.requestFocus();
        } else {
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      if (n >= maxAttempts || !_r.episodeScrollController.hasClients) {
        if (_deps.isTelevision()) node.requestFocus(); // best effort, then stop
        return;
      }
      final pos = _r.episodeScrollController.position;
      final ratio = episodeCount > 1 ? epIndex / (episodeCount - 1) : 0.0;
      final target = (pos.maxScrollExtent * ratio).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if ((target - pos.pixels).abs() > 1.0) {
        _r.episodeScrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt(n + 1));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(0));
  }
}
