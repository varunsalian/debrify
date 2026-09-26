import 'keyword_cache_state.dart';
import 'keyword_providers.dart';
import 'keyword_results_state.dart';

/// Completed keyword results retained for one tab variant in a profile session.
/// Only the legacy persisted choices survive; transient interaction state does not.
class KeywordSnapshot {
  final String variant;
  final String query;
  final KeywordResultsState projection;
  final KeywordCacheState cache;
  final double scrollOffset;

  KeywordSnapshot({
    required this.variant,
    required this.query,
    required KeywordResultsState projection,
    required this.cache,
    required this.scrollOffset,
  }) : projection = projection.copyWith(
         clearPending: true,
         frozen: false,
         selectionMode: false,
         selected: {},
         providers: KeywordProviders(
           directCounts: projection.providers.directCounts,
           torrentCounts: projection.providers.torrentCounts,
           selectedDirect: projection.providers.selectedDirect,
           selectedTorrent: projection.providers.selectedTorrent,
           seen: {},
         ),
       );
}
