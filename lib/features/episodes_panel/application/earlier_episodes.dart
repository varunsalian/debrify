// "Mark earlier episodes watched": the pure policy for which episodes count
// as earlier than a target, and how a batch mark fans out per provider and
// season. No UI, no I/O — the production mark callback is passed in.
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter/foundation.dart';

typedef EpisodeRef = ({int season, int episode});

/// Every aired episode before ([season], [episode]), ordered by season then
/// episode.
///
/// - Regular target (season >= 1): episodes of seasons 1..season-1, plus
///   episodes of [season] with a number below [episode]. Specials (season 0)
///   are never included.
/// - Special target (season 0): only specials with a lower number.
/// - An episode whose `firstAired` parses (DateTime.tryParse) to a moment
///   after [now] is unaired and skipped; a null/unparsable `firstAired`
///   counts as aired.
/// - Duplicate (season, episode) pairs appear once.
List<EpisodeRef> earlierEpisodes(
  List<TraktSeason> seasons, {
  required int season,
  required int episode,
  required DateTime now,
}) {
  final seen = <EpisodeRef>{};
  final refs = <EpisodeRef>[];
  for (final seasonEntry in seasons) {
    for (final ep in seasonEntry.episodes) {
      final key = (season: ep.season, episode: ep.number);
      final isEarlier = season == 0
          ? ep.season == 0 && ep.number < episode
          : (ep.season >= 1 && ep.season < season) ||
                (ep.season == season && ep.number < episode);
      if (!isEarlier) continue;
      final aired = ep.firstAired;
      if (aired != null) {
        final moment = DateTime.tryParse(aired);
        if (moment != null && moment.isAfter(now)) continue;
      }
      if (seen.add(key)) refs.add(key);
    }
  }
  refs.sort((a, b) {
    final bySeason = a.season.compareTo(b.season);
    return bySeason != 0 ? bySeason : a.episode.compareTo(b.episode);
  });
  return refs;
}

/// Result of a batch mark: how many episodes were marked, and failures per
/// provider.
@immutable
final class EarlierEpisodesResult {
  const EarlierEpisodesResult({
    required this.marked,
    required this.failed,
    this.cancelled = false,
  });

  /// Number of episodes in the batch.
  final int marked;

  /// Provider → failed episode count; only non-zero entries.
  final Map<TrackingSource, int> failed;

  /// Stopped early because `canContinue()` turned false.
  final bool cancelled;

  bool get hasFailures => failed.isNotEmpty;
}

/// Returns the number of episodes that FAILED (0 = all marked), like
/// SeasonWatchedService.mark.
typedef SeasonMark =
    Future<int> Function(
      String imdbId,
      int season,
      Iterable<int> episodes,
      TrackingSource provider, {
      String? seriesTitle,
    });

/// Marks [episodes] watched on every provider in [providers]: one [mark]
/// call per (provider, season), providers in the order given, seasons
/// ascending, episode numbers as a sorted list. [seriesTitle] is passed
/// through on every call. A [mark] that throws counts every episode of that
/// season as failed for that provider; the rest still run. [canContinue] is
/// checked before every [mark] call; when it returns false the batch stops
/// and the result has `cancelled: true` (a profile switch mid-batch must not
/// write on).
Future<EarlierEpisodesResult> markEarlierEpisodesWatched({
  required String imdbId,
  required String seriesTitle,
  required List<EpisodeRef> episodes,
  required List<TrackingSource> providers,
  required SeasonMark mark,
  bool Function()? canContinue,
}) async {
  final numbersBySeason = <int, List<int>>{};
  for (final ref in episodes) {
    numbersBySeason.putIfAbsent(ref.season, () => []).add(ref.episode);
  }
  final seasons = numbersBySeason.keys.toList()..sort();
  for (final numbers in numbersBySeason.values) {
    numbers.sort();
  }

  var cancelled = false;
  final failed = <TrackingSource, int>{};
  for (final provider in providers) {
    if (cancelled) break;
    for (final season in seasons) {
      if (canContinue != null && !canContinue()) {
        cancelled = true;
        break;
      }
      final numbers = numbersBySeason[season]!;
      int failedCount;
      try {
        failedCount = await mark(
          imdbId,
          season,
          numbers,
          provider,
          seriesTitle: seriesTitle,
        );
      } catch (_) {
        failedCount = numbers.length;
      }
      if (failedCount > 0) {
        failed[provider] = (failed[provider] ?? 0) + failedCount;
      }
    }
  }
  return EarlierEpisodesResult(
    marked: episodes.length,
    failed: failed,
    cancelled: cancelled,
  );
}
