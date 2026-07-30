/// Picks a deterministic, real episode from metadata rows returned by Stremio
/// or TVMaze.
///
/// Stremio rows normally use `season` + `number` and TVMaze uses the same
/// fields. A few addons use `episode` instead of `number`, so both are accepted.
class StremioTvEpisodePicker {
  StremioTvEpisodePicker._();

  static ({int season, int episode})? pick(
    Iterable<dynamic> rows, {
    required String seed,
    DateTime? now,
    bool requireAirDate = false,
  }) {
    final cutoff = now ?? DateTime.now();
    final episodes = <({int season, int episode})>[];
    final seen = <String>{};

    for (final row in rows) {
      if (row is! Map) continue;
      final season = _positiveInt(row['season']);
      final episode = _positiveInt(row['number'] ?? row['episode']);
      if (season == null ||
          episode == null ||
          !_hasAired(row, cutoff, requireAirDate: requireAirDate)) {
        continue;
      }

      final key = '$season:$episode';
      if (seen.add(key)) {
        episodes.add((season: season, episode: episode));
      }
    }

    if (episodes.isEmpty) return null;
    final hash = _djb2('episode:$seed');
    return episodes[hash % episodes.length];
  }

  static int? _positiveInt(dynamic value) {
    final parsed = switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static bool _hasAired(
    Map<dynamic, dynamic> row,
    DateTime cutoff, {
    required bool requireAirDate,
  }) {
    final raw =
        row['released'] ??
        row['airstamp'] ??
        row['airdate'] ??
        row['firstAired'];
    if (raw == null) return !requireAirDate;
    final date = DateTime.tryParse(raw.toString());
    if (date == null) return !requireAirDate;
    return !date.isAfter(cutoff);
  }

  static int _djb2(String input) {
    var hash = 5381;
    for (var i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
      hash &= 0x7FFFFFFF;
    }
    return hash;
  }
}
