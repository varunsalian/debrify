// Sport-level views of the board: the sport chips' counts, narrowing the
// rows to one sport, and the catalog grouped by sport for the league picker.
//
// Application layer: pure functions over immutable models. Sports are ordered
// by the most important league each has in the catalog, so the chips and the
// picker list the same sports in the same order.
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// One sport chip: the sport and how many distinct fixtures it has.
typedef SportsBoardSportCount = ({SportKind sport, int count});

/// One sport of the league picker with its catalog leagues, most important
/// first.
typedef SportsLeagueGroup = ({SportKind sport, List<SportsLeague> leagues});

/// The sport of [event]'s league; null for a league outside the catalog.
SportKind? sportsEventSport(SportsEvent event) =>
    sportsLeagueById(event.leagueId)?.sport;

/// Each sport present in [sections] with its distinct fixture count, in
/// [sportsKindRank] order. Fixtures of unknown leagues count only under All.
List<SportsBoardSportCount> sportsBoardSportCounts(
  List<SportsBoardSection> sections,
) {
  final seen = <String>{};
  final counts = <SportKind, int>{};
  for (final section in sections) {
    for (final event in section.events) {
      if (!seen.add('${event.leagueId}/${event.id}')) continue;
      final sport = sportsEventSport(event);
      if (sport != null) counts[sport] = (counts[sport] ?? 0) + 1;
    }
  }
  final sports = counts.keys.toList()..sort(_bySportRank);
  return [for (final sport in sports) (sport: sport, count: counts[sport]!)];
}

/// [sections] narrowed to [sport], dropping rows left empty; null keeps all.
List<SportsBoardSection> sportsBoardSectionsForSport(
  List<SportsBoardSection> sections,
  SportKind? sport,
) {
  if (sport == null) return sections;
  return [
    for (final section in sections)
      if (section.events.where((e) => sportsEventSport(e) == sport).toList()
          case final events when events.isNotEmpty)
        SportsBoardSection(
          id: section.id,
          title: section.title,
          events: events,
        ),
  ];
}

/// [catalog] grouped by sport in [sportsKindRank] order; each group's leagues
/// by importance, then catalog order.
List<SportsLeagueGroup> sportsLeagueGroups(List<SportsLeague> catalog) {
  final bySport = <SportKind, List<SportsLeague>>{};
  for (final league in catalog) {
    (bySport[league.sport] ??= []).add(league);
  }
  final sports = bySport.keys.toList()..sort(_bySportRank);
  return [
    for (final sport in sports)
      (sport: sport, leagues: _byImportance(bySport[sport]!)),
  ];
}

/// The highest catalog importance of [sport]'s leagues; 0 when it has none.
int sportsKindRank(SportKind sport) => _sportRanks[sport] ?? 0;

final Map<SportKind, int> _sportRanks = () {
  final ranks = <SportKind, int>{};
  for (final league in kSportsLeagues) {
    final rank = ranks[league.sport];
    if (rank == null || league.importance > rank) {
      ranks[league.sport] = league.importance;
    }
  }
  return ranks;
}();

int _bySportRank(SportKind a, SportKind b) {
  final byRank = sportsKindRank(b).compareTo(sportsKindRank(a));
  return byRank != 0 ? byRank : a.index.compareTo(b.index);
}

/// Stable: equal importance keeps catalog order.
List<SportsLeague> _byImportance(List<SportsLeague> leagues) {
  final indexed = [...leagues.indexed];
  indexed.sort((a, b) {
    final byImportance = b.$2.importance.compareTo(a.$2.importance);
    return byImportance != 0 ? byImportance : a.$1.compareTo(b.$1);
  });
  return [for (final (_, league) in indexed) league];
}
