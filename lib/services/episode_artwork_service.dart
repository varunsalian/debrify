import 'dart:convert';
import '../models/metadata_preferences.dart';
import 'metadata_preferences_service.dart';
import 'metadata_episode_service.dart';
import 'profiles/profile_runtime.dart';
import 'trakt/trakt_episode_model.dart';
import '../utils/continue_watching_presentation.dart';
import '../models/stremio_addon.dart';
import 'stremio_service.dart';
import 'tvmaze_service.dart';

/// Resolves a landscape still for a specific episode, with session memoization.
///
/// Stremio meta is preferred because it is already the episode panel's richest
/// source. TVMaze fills gaps for tracker rows and addons without thumbnails.
class EpisodeArtworkService {
  EpisodeArtworkService({
    Future<MetadataPreferences> Function()? preferencesLoader,
    MetadataEpisodeService? metadataEpisodes,
  }) : _preferencesLoader =
           preferencesLoader ?? MetadataPreferencesService.load,
       _metadataEpisodes = metadataEpisodes ?? MetadataEpisodeService.instance;

  static final EpisodeArtworkService instance = EpisodeArtworkService();
  final Future<MetadataPreferences> Function() _preferencesLoader;
  final MetadataEpisodeService _metadataEpisodes;

  final Map<String, Future<String?>> _memo = {};

  Future<String?> resolve({
    required String imdbId,
    required int season,
    required int episode,
  }) async {
    final MetadataPreferences prefs;
    try {
      prefs = await _preferencesLoader();
    } catch (_) {
      // A profile transition can invalidate the preference read. Artwork is
      // optional; it must not fail an entire Continue Watching refresh.
      return null;
    }
    final key =
        '${ProfileRuntime.scope.value?.sessionEpoch}:${jsonEncode(prefs.toJson())}:${imdbId.toLowerCase()}:$season:$episode';
    while (_memo.length >= 256) {
      _memo.remove(_memo.keys.first);
    }
    final pending = _memo.putIfAbsent(key, () async {
      if (prefs.provider(MetadataCategory.episodeArtwork) !=
          MetadataPreferences.current) {
        final row = TraktSeason(
          number: season,
          episodeCount: 1,
          episodes: [TraktEpisode(season: season, number: episode, title: '')],
        );
        final result = await _metadataEpisodes.present(
          StremioMeta(id: imdbId, imdbId: imdbId, type: 'series', name: ''),
          row,
          preferences: prefs.copyWith(
            providers: {
              ...prefs.providers,
              MetadataCategory.episodeInformation: MetadataPreferences.current,
            },
          ),
        );
        final image = result.episodes.first.thumbnailUrl;
        if (image != null || !prefs.fallback) return image;
      }
      return _resolve(imdbId: imdbId, season: season, episode: episode);
    });
    try {
      final result = await pending;
      if (result == null &&
          prefs.provider(MetadataCategory.episodeArtwork) !=
              MetadataPreferences.current &&
          identical(_memo[key], pending)) {
        _memo.remove(key);
      }
      return result;
    } catch (_) {
      if (identical(_memo[key], pending)) _memo.remove(key);
      return null;
    }
  }

  Future<String?> _resolve({
    required String imdbId,
    required int season,
    required int episode,
  }) async {
    try {
      final addon = await StremioService.instance.firstMetaCapableAddon();
      if (addon != null) {
        final videos = await StremioService.instance.fetchSeriesMeta(
          addon,
          imdbId,
        );
        final thumbnail = episodeThumbnailFromVideos(
          videos,
          season: season,
          episode: episode,
        );
        if (thumbnail != null) return thumbnail;
      }
    } catch (_) {
      // Best-effort enrichment; TVMaze below may still know the episode.
    }

    try {
      final show = await TVMazeService.lookupByImdbId(imdbId);
      final showId = show?['id'] as int?;
      if (showId == null) return null;
      final episodes = await TVMazeService.getEpisodes(showId);
      for (final raw in episodes) {
        if ((raw['season'] as num?)?.toInt() != season ||
            (raw['number'] as num?)?.toInt() != episode) {
          continue;
        }
        final image = raw['image'] as Map<String, dynamic>?;
        final url =
            image?['medium'] as String? ?? image?['original'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    } catch (_) {
      // The show artwork remains the card's deterministic fallback.
    }
    return null;
  }
}
