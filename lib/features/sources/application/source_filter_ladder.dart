import 'dart:async';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/filter_ladder.dart';

final class SourceFilterLadder {
  const SourceFilterLadder._();

  /// Loads the quick-play ladder: inactive (a no-op) when the user disabled
  /// "Apply filters to Quick Play" or has no default filters saved.
  /// Shared with native startup recovery to enforce the same filter policy.
  static Future<FilterLadder> loadLadder({
    bool includeSize = true,
    QuickPlayRules? rules,
  }) async {
    final useFilters =
        rules?.useFilters ?? await StorageService.getQuickPlayHonorsFilters();
    if (!useFilters) {
      return FilterLadder(const TorrentFilterState.empty());
    }
    final ladder = await FilterLadder.fromSavedDefaults();
    // Size buckets only make sense for movies: addon packs report a single
    // episode's size, so honoring a size default on a series/episode play
    // would rank against a misleading number. Strip it for non-movies.
    if (includeSize) return ladder;
    return FilterLadder(ladder.filters.copyWith(sizes: const <SizeBucket>{}));
  }

  /// The loader narration line for what the ladder found (plan §3.5), or
  /// null when there is nothing to say (inactive ladder / empty list) — so
  /// filterless plays look exactly as before. Pure; public only for tests.
  static String? ladderNote(FilterLadder ladder, List<Torrent> ordered) {
    if (!ladder.isActive || ordered.isEmpty) return null;
    final summary = ladder.filterSummary();
    final best = ladder.tierOf(ordered.first);
    final n = ordered.where((t) => ladder.tierOf(t) == best).length;
    final plural = n == 1 ? 'source' : 'sources';
    if (best == 0) {
      return 'Matching your filters ($summary) · $n $plural';
    }
    if (best >= ladder.tierCount) {
      return 'Only cam-quality sources found — playing best available';
    }
    if (best == ladder.tierCount - 1) {
      return 'Nothing matches your filters ($summary) — playing best available';
    }
    return 'No full filter match — trying '
        '${ladder.describeTier(best) ?? 'any available source'} · $n $plural';
  }
}
