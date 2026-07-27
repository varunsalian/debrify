/// A single episode from the Trakt seasons+episodes API.
class TraktEpisode {
  final int season;
  final int number;
  final String title;
  final String? overview;

  /// Community rating (0–10). Mutable so it can be backfilled from Trakt after
  /// the episode list renders — addons like Cinemeta send `rating: 0` (no real
  /// per-episode rating), which the Trakt seasons API fills in. See
  /// EpisodesPanel._enrichEpisodeRatings.
  double? rating;
  final String? firstAired;
  final int? runtime;
  final String? imdbId;

  /// Episode thumbnail URL from TVMaze (set after enrichment).
  String? thumbnailUrl;

  /// Direct stream URL for sources whose episodes ARE playable links (Xtream
  /// IPTV series). Null everywhere else — torrent-backed episodes resolve
  /// their stream through the search/debrid flow instead.
  final String? playbackUrl;

  TraktEpisode({
    required this.season,
    required this.number,
    required this.title,
    this.overview,
    this.rating,
    this.firstAired,
    this.runtime,
    this.imdbId,
    this.thumbnailUrl,
    this.playbackUrl,
  });

  /// Display title like "E01 - Pilot" or "E01" if no meaningful title.
  String get displayTitle {
    final epNum = number.toString().padLeft(2, '0');
    if (title.isNotEmpty && title != 'Episode $number') {
      return 'E$epNum - $title';
    }
    return 'Episode $epNum';
  }

  /// Format air date for display (e.g., "Jan 15, 2023").
  String? get formattedAirDate {
    if (firstAired == null) return null;
    try {
      final date = DateTime.parse(firstAired!);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return null;
    }
  }

  factory TraktEpisode.fromJson(Map<String, dynamic> json) {
    final ids = json['ids'] as Map<String, dynamic>? ?? {};
    double? rating;
    final rawRating = json['rating'];
    if (rawRating is num) {
      rating = (rawRating.toDouble() * 10).roundToDouble() / 10;
    }
    return TraktEpisode(
      season: json['season'] as int? ?? 0,
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      rating: rating,
      firstAired: json['first_aired'] as String?,
      runtime: json['runtime'] as int?,
      imdbId: ids['imdb'] as String?,
    );
  }
}

/// Sort seasons ascending with Specials (season 0) at the very end — the
/// house display order for every season list (episodes panel, Xtream series
/// bridge). Lives next to the model so the two hosts can't drift apart.
int seasonsSpecialsLast(TraktSeason a, TraktSeason b) {
  if (a.number == 0 && b.number != 0) return 1;
  if (a.number != 0 && b.number == 0) return -1;
  return a.number.compareTo(b.number);
}

/// A season containing its episodes.
class TraktSeason {
  final int number;
  final int episodeCount;
  final List<TraktEpisode> episodes;

  const TraktSeason({
    required this.number,
    required this.episodeCount,
    required this.episodes,
  });

  /// Display label: "Season 1" or "Specials" for season 0.
  String get displayLabel => number == 0 ? 'Specials' : 'Season $number';

  factory TraktSeason.fromJson(Map<String, dynamic> json) {
    final episodesRaw = json['episodes'] as List<dynamic>? ?? [];
    final episodes = episodesRaw
        .map((e) => TraktEpisode.fromJson(e as Map<String, dynamic>))
        .toList();
    return TraktSeason(
      number: json['number'] as int? ?? 0,
      episodeCount: json['episode_count'] as int? ?? episodes.length,
      episodes: episodes,
    );
  }
}
