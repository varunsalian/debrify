import 'dart:math';

import '../../../models/advanced_search_selection.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/show_shuffle.dart';

/// Existing Stremio identity rules, injected without importing its transport.
typedef HomeRandomEpisodeVideoId =
    String? Function({
      required String catalogId,
      required String? imdbId,
      required int season,
      required int episode,
      Object? videoId,
    });

/// Converts raw addon metadata into a random launch selection. The caller owns
/// metadata loading, inventory persistence, dialogs and playback dispatch.
class HomeRandomEpisodeSelector {
  const HomeRandomEpisodeSelector({
    required this.videoIdFor,
    required this.isCanonicalEpisode,
    this.chooseIndex = _chooseIndex,
  });

  final HomeRandomEpisodeVideoId videoIdFor;
  final bool Function(String, String, int, int) isCanonicalEpisode;
  final int Function(int length) chooseIndex;

  static int _chooseIndex(int length) => Random().nextInt(length);

  AdvancedSearchSelection? select({
    required StremioMeta item,
    required StremioAddon? metadataAddon,
    required String contentId,
    required String? progressId,
    required List<Map<String, dynamic>>? videos,
    required bool continuous,
    DateTime? now,
  }) {
    final episodes = <({int season, int episode, String videoId})>[];
    for (final video in videos ?? const <Map<String, dynamic>>[]) {
      final rawSeason = video['season'];
      final season = rawSeason is num ? rawSeason.toInt() : null;
      if (season == null || season <= 0) continue;
      final rawEpisode = video['number'] ?? video['episode'];
      final episode = rawEpisode is num ? rawEpisode.toInt() : null;
      if (episode == null) continue;
      if (!isShuffleEpisodeEligible({
        ...video,
        'season': season,
        'number': episode,
      }, now: now)) {
        continue;
      }
      final videoId = videoIdFor(
        catalogId: contentId,
        imdbId: progressId,
        season: season,
        episode: episode,
        videoId: video['id'],
      );
      if (videoId == null) continue;
      episodes.add((season: season, episode: episode, videoId: videoId));
    }
    if (episodes.isEmpty) return null;

    final pick = episodes[chooseIndex(episodes.length)];
    var selection = AdvancedSearchSelection(
      initialContinuousShuffle: continuous,
      imdbId: progressId ?? item.id,
      isSeries: true,
      title: item.name,
      year: item.year,
      season: pick.season,
      episode: pick.episode,
      contentType: item.type,
      posterUrl: item.poster,
    );
    if (metadataAddon != null &&
        !isCanonicalEpisode(
          selection.imdbId,
          pick.videoId,
          pick.season,
          pick.episode,
        )) {
      selection = selection.withStremioEpisodeIdentity(
        addonId: metadataAddon.id,
        addonKey: metadataAddon.sourceBindingKey,
        catalogId: contentId,
        videoId: pick.videoId,
      );
    }
    return selection;
  }
}
