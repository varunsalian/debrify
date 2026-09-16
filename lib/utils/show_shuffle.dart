import 'dart:math';

/// Stable identities keep shuffle history independent of the currently open pack.
typedef ShuffleEpisode = (int, int);

bool isShuffleEpisodeEligible(Map<String, dynamic> episode, {DateTime? now}) {
  final season = episode['season'];
  final number = episode['number'];
  if (season is! int || number is! int || season <= 0 || number <= 0) {
    return false;
  }
  final air = DateTime.tryParse(
    (episode['airstamp'] ?? episode['airdate'] ?? '').toString(),
  );
  // Unknown dates remain playable; positively future-dated episodes do not.
  return air == null || !air.isAfter(now ?? DateTime.now());
}

class ShowShuffle {
  ShowShuffle({Random? random}) : _random = random ?? Random();
  final Random _random;
  final Set<ShuffleEpisode> _visited = {};

  void clear() => _visited.clear();

  ShuffleEpisode? pick(
    Iterable<ShuffleEpisode> episodes,
    ShuffleEpisode? current, {
    Set<ShuffleEpisode> excluded = const {},
  }) {
    final eligible = episodes.toSet()..removeAll(excluded);
    eligible.remove(current);
    if (eligible.isEmpty) return null;
    if (current != null) _visited.add(current);
    var remaining = eligible.difference(_visited).toList();
    if (remaining.isEmpty) {
      _visited.clear();
      if (current != null) _visited.add(current);
      remaining = eligible.toList();
    }
    final next = remaining[_random.nextInt(remaining.length)];
    _visited.add(next);
    return next;
  }
}
