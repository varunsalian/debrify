/// Whether [query] contains any meaningful token from [initialTitle].
///
/// RD and TorBox use this predicate for initial-title search restrictions.
/// Each host owns when to apply it, empty-submit handling and focus transfer.
/// Matching deliberately uses substrings and ASCII tokens; if filtering out
/// stopwords and single characters leaves nothing, all raw tokens are used.
bool queryMatchesInitialTitle(String query, String? initialTitle) {
  final title = initialTitle;
  if (title == null || title.isEmpty) return true;
  const stopwords = {'the', 'a', 'an'};
  final rawTokens = title
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  final filtered = rawTokens
      .where((t) => !stopwords.contains(t) && t.length >= 2)
      .toList();
  final effectiveTokens = filtered.isEmpty ? rawTokens : filtered;
  if (effectiveTokens.isEmpty) return true;
  final normalizedQuery = query.toLowerCase();
  return effectiveTokens.any((t) => normalizedQuery.contains(t));
}
