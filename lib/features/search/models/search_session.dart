import 'keyword_results_state.dart';
import '../../../services/profiles/profile_session_memory.dart';
import 'keyword_cache_state.dart';

/// Mutable search state belongs to one screen in one profile session. Separate
/// routes must not share it just because they happen to have the same query.
class SearchSession {
  final ProfileSessionOwner owner;
  final Object viewIdentity;

  // Immutable bootstrap data for this one view identity. It is not a second
  // live state owner and never changes the identity of an existing workflow.
  final KeywordCacheState initialKeywordCache;
  final String initialKeywordQuery;
  final KeywordResultsState? initialKeywordResults;

  const SearchSession({
    required this.owner,
    required this.viewIdentity,
    this.initialKeywordCache = const KeywordCacheState.empty(),
    this.initialKeywordQuery = '',
    this.initialKeywordResults,
  });

  @override
  bool operator ==(Object other) =>
      other is SearchSession &&
      other.owner == owner &&
      identical(other.viewIdentity, viewIdentity);

  @override
  int get hashCode => Object.hash(owner, identityHashCode(viewIdentity));
}
