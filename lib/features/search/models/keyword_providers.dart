/// An immutable reconciliation result. The caller owns subsequent user edits.
class KeywordProviders {
  final Map<String, int> directCounts;
  final Map<String, int> torrentCounts;
  final Set<String> selectedDirect;
  final Set<String> selectedTorrent;
  final Set<String> seen;

  const KeywordProviders.empty()
    : directCounts = const {},
      torrentCounts = const {},
      selectedDirect = const {},
      selectedTorrent = const {},
      seen = const {};

  KeywordProviders({
    required Map<String, int> directCounts,
    required Map<String, int> torrentCounts,
    required Set<String> selectedDirect,
    required Set<String> selectedTorrent,
    required Set<String> seen,
  }) : directCounts = Map.unmodifiable(directCounts),
       torrentCounts = Map.unmodifiable(torrentCounts),
       selectedDirect = Set.unmodifiable(selectedDirect),
       selectedTorrent = Set.unmodifiable(selectedTorrent),
       seen = Set.unmodifiable(seen);
}
