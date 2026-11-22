/// Simkl's episode codes, as in `next_to_watch`: `"S02E06"` for TV shows,
/// `"E05"` for anime (no season; the cour's own numbering, see
/// SimklAnimeEpisodes). Shared by the Continue Watching up-next builder and
/// the series-resume fallback so they never disagree on the parse rule.
final class SimklEpisodeCodes {
  SimklEpisodeCodes._();

  /// A regular-season `SxxExx` code as season/episode. Null for anything
  /// else, including Season 0 specials and anime-style `"E148"` codes.
  static ({int season, int episode})? seasonEpisode(dynamic value) {
    if (value is! String) return null;
    final m = RegExp(r'^[Ss](\d+)[Ee](\d+)$').firstMatch(value.trim());
    if (m == null) return null;
    final s = int.tryParse(m.group(1)!);
    final e = int.tryParse(m.group(2)!);
    if (s == null || s <= 0 || e == null || e <= 0) return null;
    return (season: s, episode: e);
  }

  /// The episode number of an anime-style `"E05"` code. Null for anything
  /// else.
  static int? absolute(dynamic code) {
    if (code is! String) return null;
    final match = RegExp(r'^[Ee](\d+)$').firstMatch(code.trim());
    final number = match == null ? null : int.tryParse(match.group(1)!);
    return number != null && number > 0 ? number : null;
  }
}
