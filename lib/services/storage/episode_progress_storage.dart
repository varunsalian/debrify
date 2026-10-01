import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';

final class EpisodeProgressStorage {
  const EpisodeProgressStorage._();

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final currentTitleKey = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty ? null : normalizedImdbId;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> || seriesData['type'] != 'series') {
        continue;
      }
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final storedImdbId = seriesData['imdbId']?.toString().trim().toLowerCase();
      final matchesStableId = stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      final finishedEpisodes = seriesData['finishedEpisodes'];
      if (finishedEpisodes is! Map) continue;
      final seasonData = finishedEpisodes[season.toString()];
      if (seasonData is Map && seasonData.containsKey(episode.toString())) {
        return true;
      }
    }
    return false;
  }

  /// Get all finished episodes for a series
  static Future<Map<String, Set<int>>> getFinishedEpisodes({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes == null) return {};

    final result = <String, Set<int>>{};

    for (final seasonEntry in finishedEpisodes.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;
      result[season] = episodes.keys.map((e) => int.parse(e)).toSet();
    }

    return result;
  }

  /// Resolve finished episodes by stable title identity, falling back to the
  /// historical title-keyed record for installs created before IMDb IDs were
  /// persisted with series playback.
  static Future<Map<String, Set<int>>> getFinishedEpisodesByImdbId({
    required String imdbId,
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, Set<int>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      if (storedId != normalized) continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      for (final entry in finished.entries) {
        final episodes = entry.value;
        if (episodes is! Map) continue;
        result.putIfAbsent(entry.key.toString(), () => <int>{}).addAll({
          for (final episode in episodes.keys)
            if (int.tryParse(episode.toString()) case final value?) value,
        });
      }
    }
    if (result.isNotEmpty) return result;
    if (!PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) &&
        seriesTitle != null &&
        seriesTitle.isNotEmpty) {
      // Only ID-less legacy records may provide title fallback. A matching
      // display title does not make another IMDb series the same show.
      final index = await getFinishedSeriesEpisodeIndex();
      return index['title:${seriesTitle.trim().toLowerCase()}'] ?? {};
    }
    return {};
  }

  /// One-pass index for derived series completion. IMDb keys are preferred;
  /// title keys preserve older playback records that predate stable IDs.
  static Future<Map<String, Map<String, Set<int>>>> getFinishedSeriesEpisodeIndex() async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, Map<String, Set<int>>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      final parsed = <String, Set<int>>{
        for (final entry in finished.entries)
          entry.key.toString(): {
            if (entry.value is Map)
              for (final episode in (entry.value as Map).keys)
                if (int.tryParse(episode.toString()) case final value?) value,
          },
      };
      void mergeInto(String key) {
        final target = result.putIfAbsent(key, () => <String, Set<int>>{});
        for (final season in parsed.entries) {
          target.putIfAbsent(season.key, () => <int>{}).addAll(season.value);
        }
      }

      final imdbId = raw['imdbId']?.toString().trim().toLowerCase();
      if (imdbId != null && imdbId.isNotEmpty) {
        mergeInto(imdbId);
        continue;
      }
      final title = raw['title']?.toString().trim().toLowerCase();
      if (title != null && title.isNotEmpty) mergeInto('title:$title');
    }
    return result;
  }

  /// Get episode progress for a series
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgress({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final seasons = seriesData['seasons'];
    if (seasons == null) return {};

    final result = <String, Map<String, dynamic>>{};

    for (final seasonEntry in seasons.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;

      for (final episodeEntry in episodes.entries) {
        final episode = episodeEntry.key;
        final episodeData = episodeEntry.value as Map<String, dynamic>;
        final episodeKey = '${season}_$episode';
        result[episodeKey] = episodeData;
      }
    }

    return result;
  }
}
