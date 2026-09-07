/// Does [query] carry any meaningful token of [initialTitle]?
///
/// Moved from the byte-identical `_queryMatchesInitialTitle` the TorBox and
/// Real-Debrid cloud files screens each carried (G4-5). It gates submitting a
/// torrent search while a host is in select-source mode and hidden from nav,
/// so the user cannot wander off the title they came in with.
///
/// Behaviour is unchanged, including its quirks:
/// * an empty or absent [initialTitle] matches everything;
/// * tokens are the title lowercased and split on non-alphanumerics, minus
///   the stopwords {the, a, an} and minus single characters — but if that
///   filter empties the list, the unfiltered tokens are used instead;
/// * matching is *containment*, not word equality, so "prematrixed" is an
///   accepted query for "The Matrix".
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
