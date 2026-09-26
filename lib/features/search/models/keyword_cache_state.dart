class KeywordCacheState {
  final Map<String, List<String>> badges;
  final bool cachedOnly;

  const KeywordCacheState.empty({this.cachedOnly = false}) : badges = const {};

  KeywordCacheState({
    required Map<String, List<String>> badges,
    required this.cachedOnly,
  }) : badges = Map.unmodifiable({
         for (final entry in badges.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });
}
