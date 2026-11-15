import 'package:flutter/foundation.dart';

import '../models/stremio_addon.dart';
import '../models/trakt/trakt_calendar_entry.dart';
import 'mdblist/mdblist_calendar_service.dart';
import 'mdblist/mdblist_service.dart';
import 'simkl/simkl_calendar_service.dart';
import 'simkl/simkl_service.dart';
import 'trakt/trakt_calendar_service.dart';
import 'trakt/trakt_service.dart';

/// The next episode a Home "Airing soon" card stands for.
class HomeAiringEpisode {
  const HomeAiringEpisode({
    required this.season,
    required this.episode,
    required this.label,
  });

  final int season;
  final int episode;

  /// The card badge: "Today · S2E5", "Tomorrow · S1E1", "Fri · S3E10".
  final String label;
}

/// What an "Airing soon" row carries beyond its posters: each show's next
/// episode (keyed by [StremioMeta.id]) and whether Trakt supplied it, so the
/// detail page opens with Trakt semantics like the Calendar does.
class HomeAiringRow {
  const HomeAiringRow({required this.episodes, required this.fromTrakt});

  final Map<String, HomeAiringEpisode> episodes;
  final bool fromTrakt;
}

/// Builds and loads the opt-in "Airing soon" Home row from the same tracker
/// calendars the Calendar tab reads, picking the source the same way: Trakt,
/// then Simkl, then MDBList, whichever is connected first.
class HomeAiringSoon {
  HomeAiringSoon._();

  /// How far ahead the row looks.
  static const int days = 7;

  /// Most shows the row holds.
  static const int maxShows = 20;

  static Future<({List<StremioMeta> items, HomeAiringRow? row, bool failed})>
  load({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final end = today.add(const Duration(days: days));
    try {
      final Map<DateTime, List<TraktCalendarEntry>> grouped;
      final bool fromTrakt;
      if (await TraktService.instance.isAuthenticated()) {
        fromTrakt = true;
        grouped = await TraktCalendarService.instance.getRange(
          today,
          end,
          strict: true,
        );
      } else if (await SimklService.instance.isAuthenticated()) {
        fromTrakt = false;
        grouped = await SimklCalendarService.instance.getRange(
          today,
          end,
          strict: true,
        );
      } else if (await MdblistService.instance.isAuthenticated()) {
        fromTrakt = false;
        grouped = await MdblistCalendarService.instance.getRange(
          today,
          end,
          strict: true,
        );
      } else {
        return (items: const <StremioMeta>[], row: null, failed: false);
      }
      final built = build(
        [for (final day in grouped.values) ...day],
        now: at,
        exactTimes: fromTrakt,
      );
      return (
        items: built.items,
        row: HomeAiringRow(episodes: built.episodes, fromTrakt: fromTrakt),
        failed: false,
      );
    } catch (error) {
      // The row keeps what it showed; leave a trace of why. Type only: a
      // message could carry a URL.
      debugPrint('HomeAiringSoon: calendar read failed (${error.runtimeType})');
      return (items: const <StremioMeta>[], row: null, failed: true);
    }
  }

  /// One card per show for its soonest episode still to come, soonest first.
  ///
  /// Trakt gives real air times ([exactTimes]), so an episode that already
  /// aired earlier today is left out. Simkl and MDBList give only a day, so
  /// everything dated today stays. Shows without an IMDb id are skipped: the
  /// detail page can't open them.
  static ({List<StremioMeta> items, Map<String, HomeAiringEpisode> episodes})
  build(
    List<TraktCalendarEntry> entries, {
    required DateTime now,
    required bool exactTimes,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = [
      for (final e in entries)
        if ((e.showImdbId ?? '').startsWith('tt') &&
            (exactTimes
                ? e.firstAiredLocal.isAfter(now)
                : !_day(e.firstAiredLocal).isBefore(today)))
          e,
    ]..sort(_soonestFirst);
    final items = <StremioMeta>[];
    final episodes = <String, HomeAiringEpisode>{};
    for (final e in upcoming) {
      final id = e.showImdbId!;
      if (episodes.containsKey(id)) continue;
      episodes[id] = HomeAiringEpisode(
        season: e.seasonNumber,
        episode: e.episodeNumber,
        label:
            '${dayLabel(e.firstAiredLocal, today)} · '
            'S${e.seasonNumber}E${e.episodeNumber}',
      );
      items.add(
        StremioMeta(
          id: id,
          imdbId: id,
          type: 'series',
          name: e.showTitle,
          poster: e.posterUrl,
          year: e.showYear?.toString(),
        ),
      );
      if (items.length == maxShows) break;
    }
    return (items: items, episodes: episodes);
  }

  /// "Today", "Tomorrow", then the short weekday: the row spans one week, so
  /// a weekday name is never ambiguous.
  static String dayLabel(DateTime when, DateTime today) {
    // Whole calendar days, counted in UTC so a 23- or 25-hour DST day can't
    // shift "Tomorrow" to "Today".
    final diff = DateTime.utc(
      when.year,
      when.month,
      when.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[when.weekday - 1];
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static int _soonestFirst(TraktCalendarEntry a, TraktCalendarEntry b) {
    final byTime = a.firstAiredLocal.compareTo(b.firstAiredLocal);
    if (byTime != 0) return byTime;
    final bySeason = a.seasonNumber.compareTo(b.seasonNumber);
    return bySeason != 0
        ? bySeason
        : a.episodeNumber.compareTo(b.episodeNumber);
  }
}
