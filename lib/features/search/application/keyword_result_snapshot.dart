import '../models/keyword_results_state.dart';
import 'keyword_providers.dart';

/// Fold authoritative pending raw rows and provider choices for tab return,
/// retaining the legacy displayed filtered rows. Pure: callable during widget
/// disposal using a retained subscription, without resolving or mutating providers.
KeywordResultsState keywordResultsSnapshot(KeywordResultsState state) {
  final pending = state.pending;
  if (pending == null) return state;
  return state.copyWith(
    all: pending,
    providers: reconcileKeywordProviders(
      pending,
      selectedDirect: state.providers.selectedDirect,
      selectedTorrent: state.providers.selectedTorrent,
      seen: state.providers.seen,
    ),
    clearPending: true,
    clearSourceTab: !pending.any(
      (row) => keywordSourceOf(row) == state.sourceTab,
    ),
  );
}
