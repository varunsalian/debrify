import 'dart:async';
import 'package:debrify/features/episodes_panel/application/episodes_panel_policies.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter/material.dart';

class EpisodesPanelSeasons {
  final EpisodesPanelDeps _deps;
  EpisodesPanelSeasons(this._deps);
  EpisodesPanelServices get _sv => _deps.parts.services;

  /// Build the season list from the title's own addon or built-in guide.
  /// The built-in guide includes its own Trakt fallback; other addons and
  /// placeholder sources fall back to Trakt here.
  Future<List<TraktSeason>> fetchSeasons(StremioMeta show) async {
    // 0) Direct-source mode: the loader is the only season source — a failure
    //    surfaces the retry panel rather than falling through to fetchers
    //    that cannot know this show.
    final directLoader = _deps.seasonsLoader();
    if (directLoader != null) {
      try {
        return await directLoader();
      } catch (e) {
        debugPrint('EpisodesPanel: direct seasons fetch failed: $e');
        return [];
      }
    }

    // 1) The title's own addon, or built-in metadata for tracker cards.
    if (_deps.addon().id == NativeSeriesMetadataService.addon.id ||
        MediaIdentity.isNative(show.id) ||
        _deps.addon().baseUrl.isNotEmpty ||
        _deps.addon().manifestUrl.isNotEmpty) {
      try {
        final videos = await _sv.stremioService.fetchSeriesMeta(
          _deps.addon(),
          show.id,
        );
        final seasons = groupVideosIntoSeasons(videos);
        if (seasons.isNotEmpty ||
            _deps.addon().id == NativeSeriesMetadataService.addon.id) {
          return seasons;
        }
      } catch (e) {
        debugPrint('EpisodesPanel: addon meta fetch failed: $e');
      }
    }

    // 2) Trakt public seasons API (no auth required; keyed off the IMDb id).
    if (CustomSeriesIdentity.isCustom(show.imdbId)) return [];
    final traktId = show.progressId ?? show.id;
    if (MediaIdentity.isImdb(traktId)) {
      try {
        final raw = await _sv.traktService.fetchShowSeasons(traktId);
        // Dedupe by season number: a malformed response can yield >1 season
        // that both default to number 0, which would give the season dropdown
        // two items with the same value and trip its assertion. seen.add()
        // returns false for a number already present, dropping the duplicate.
        final seen = <int>{};
        final seasons =
            raw
                .map((s) => TraktSeason.fromJson(s))
                // Keep Specials (season 0); drop negatives and duplicate numbers.
                .where(
                  (s) =>
                      s.number >= 0 &&
                      s.episodes.isNotEmpty &&
                      seen.add(s.number),
                )
                .toList()
              ..sort(seasonsSpecialsLast);
        if (seasons.isNotEmpty) return seasons;
      } catch (e) {
        debugPrint('EpisodesPanel: Trakt seasons fetch failed: $e');
      }
    }

    return [];
  }

  /// Group raw Stremio addon meta `videos` into seasons, sorted by season then
  /// episode with Specials (season 0) last. Returns an empty list when there is
  /// nothing usable (null/empty input).
  List<TraktSeason> groupVideosIntoSeasons(List<Map<String, dynamic>>? videos) {
    if (videos == null || videos.isEmpty) return [];

    final seasonMap = <int, List<TraktEpisode>>{};
    for (final v in videos) {
      final seasonRaw = v['season'];
      final seasonNum = seasonRaw is int
          ? seasonRaw
          : (seasonRaw is num ? seasonRaw.toInt() : null);
      // Keep Specials (season 0); drop only invalid/negative season numbers.
      if (seasonNum == null || seasonNum < 0) continue;

      final epRaw = v['number'] ?? v['episode'];
      final epNum = epRaw is int
          ? epRaw
          : (epRaw is num ? epRaw.toInt() : null);
      if (epNum == null) continue;

      final title = (v['title'] as String?) ?? (v['name'] as String?) ?? '';
      final overview = v['overview'] as String?;
      final released = v['released'] as String?;
      final thumbnail = EpisodesPanelPolicies.downsizeMetahubThumb(
        v['thumbnail'] as String?,
      );
      final ratingRaw = v['imdbRating'] ?? v['rating'];
      final rating = ratingRaw is num
          ? ratingRaw.toDouble()
          : (ratingRaw is String ? double.tryParse(ratingRaw) : null);

      final episode = TraktEpisode(
        season: seasonNum,
        number: epNum,
        title: title,
        overview: overview,
        firstAired: released,
        thumbnailUrl: thumbnail,
        rating: rating,
        stremioVideoId: v['id']?.toString(),
      );

      seasonMap.putIfAbsent(seasonNum, () => []);
      seasonMap[seasonNum]!.add(episode);
    }

    if (seasonMap.isEmpty) return [];

    return seasonMap.entries.map((e) {
      final episodes = e.value..sort((a, b) => a.number.compareTo(b.number));
      return TraktSeason(
        number: e.key,
        episodeCount: episodes.length,
        episodes: episodes,
      );
    }).toList()..sort(seasonsSpecialsLast);
  }
}
