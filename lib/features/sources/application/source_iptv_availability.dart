import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';

final class SourceIptvAvailability {
  const SourceIptvAvailability._();

  /// A deferred Xtream row proves only that the provider has a matching
  /// series title, not that it has the requested episode. At a fallback
  /// boundary, resolve rows in priority order until one real episode exists.
  /// Failed rows are removed so their placeholder identity cannot suppress an
  /// existing torrent/pack fallback. Ordinary playable candidates keep the
  /// fully lazy path unchanged.
  static Future<List<Torrent>> confirmDeferredIptvAvailability(
    List<Torrent> sources, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
    Duration timeout = iptvQuickPlaySearchTimeout,
    Future<IptvEpisodeResolution> Function(
      Torrent source, {
      int? season,
      int? episode,
    })?
    resolver,
  }) async {
    if (sources.any(
      (source) =>
          SourceCandidateRanking.isAutoPlayableCandidate(source) &&
          !IptvSourceSearch.isDeferredXtreamSeries(source),
    )) {
      return sources;
    }
    final pending = sources
        .where(IptvSourceSearch.isDeferredXtreamSeries)
        .toList();
    if (pending.isEmpty) return sources;

    final remaining = List<Torrent>.of(sources);
    final resolve = resolver ?? IptvSourceSearch.resolveXtreamSeriesEpisode;
    final deadline = DateTime.now().add(timeout);
    logIptvSourceEvent(
      'quick_play_fallback_gate_started',
      catalogType: 'series',
      season: season,
      episode: episode,
      candidateCount: pending.length,
    );
    for (final descriptor in pending) {
      if (isCancelled?.call() ?? false) return remaining;
      final timeLeft = deadline.difference(DateTime.now());
      if (timeLeft <= Duration.zero) break;
      IptvEpisodeResolution resolution;
      try {
        resolution = await resolve(descriptor, season: season, episode: episode)
            .timeout(
              timeLeft,
              onTimeout: () => const IptvEpisodeResolution(
                IptvEpisodeResolutionStatus.unavailable,
              ),
            );
      } catch (error) {
        resolution = const IptvEpisodeResolution(
          IptvEpisodeResolutionStatus.unavailable,
        );
        logIptvSourceEvent(
          'quick_play_fallback_gate_candidate',
          source: descriptor,
          stage: 'episode_resolution',
          outcome: 'unavailable',
          season: season,
          episode: episode,
          error: error,
        );
      }
      final resolved = resolution.source;
      final index = remaining.indexOf(descriptor);
      if (resolved != null) {
        if (index >= 0) remaining[index] = resolved;
        logIptvSourceEvent(
          'quick_play_fallback_gate_completed',
          source: resolved,
          outcome: 'playable',
          season: season,
          episode: episode,
        );
        return remaining;
      }
      if (index >= 0) remaining.removeAt(index);
      logIptvSourceEvent(
        'quick_play_fallback_gate_candidate',
        source: descriptor,
        stage: 'episode_resolution',
        outcome: resolution.status.name,
        season: season,
        episode: episode,
      );
    }
    // A timeout is inconclusive for the provider, but still cannot count as a
    // playable result for this attempt. Remove any descriptors not reached.
    remaining.removeWhere(IptvSourceSearch.isDeferredXtreamSeries);
    logIptvSourceEvent(
      'quick_play_fallback_gate_completed',
      catalogType: 'series',
      outcome: 'no_playable_episode',
      season: season,
      episode: episode,
    );
    return remaining;
  }

  static const iptvQuickPlaySearchTimeout = Duration(minutes: 1);
}
