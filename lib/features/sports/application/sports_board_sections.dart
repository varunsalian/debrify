// Turns a flat event list into the ordered rows the board renders.
//
// Application layer: pure functions over immutable models — no fetching, no
// persistence, no UI. Each base list owns its eligibility rule and its sort;
// the active [SportsBoardFilter] only decides which lists appear, in which
// order, and empty lists are dropped so the view never renders a blank row.
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';

/// Board filters, one per segmented-control choice.
enum SportsBoardFilter { live, today, week, following }

/// One titled row of the board.
@immutable
class SportsBoardSection {
  const SportsBoardSection({
    required this.id,
    required this.title,
    required this.events,
  });

  /// Stable row identity, e.g. `'later-today'`.
  final String id;

  /// Row heading shown above the cards.
  final String title;

  /// Already sorted; never empty in a returned list.
  final List<SportsEvent> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsBoardSection &&
          other.id == id &&
          other.title == title &&
          listEquals(other.events, events));

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(events));

  @override
  String toString() => 'SportsBoardSection($id, ${events.length})';
}

const Duration _oneDay = Duration(days: 1);
const Duration _oneWeek = Duration(days: 7);
const Duration _twentyFourHours = Duration(hours: 24);

/// The rows for [filter], in display order, omitting empty ones.
///
/// "Today" and the week window are local calendar days of [now], never UTC
/// days, so a 23:00 UTC fixture lands on the day the user sees.
List<SportsBoardSection> buildSportsBoardSections({
  required List<SportsEvent> events,
  required SportsFollows follows,
  required DateTime now,
  required SportsBoardFilter filter,
}) {
  final sections = switch (filter) {
    SportsBoardFilter.live => [_live(events, follows)],
    SportsBoardFilter.today => [
      _live(events, follows),
      _yourTeams(events, follows, now, todayOnly: true),
      _laterToday(events, now),
      _earlierToday(events, now),
    ],
    SportsBoardFilter.week => [
      _live(events, follows),
      _yourTeams(events, follows, now),
      _laterToday(events, now),
      _thisWeek(events, now),
      _earlierToday(events, now),
    ],
    SportsBoardFilter.following => [
      _live(events, follows, followedOnly: true),
      _upcoming(events, follows, now),
      _recentResults(events, follows, now),
    ],
  };
  return [
    for (final section in sections)
      if (section != null) section,
  ];
}

/// The event to feature above the rows, or null when nothing deserves it.
///
/// Followed live events win over any live event, which win over the next
/// followed fixture starting within the next 24 hours (both bounds inclusive).
SportsEvent? pickSportsHero(
  List<SportsEvent> events,
  SportsFollows follows,
  DateTime now,
) {
  final hero =
      _bestLive(events, follows, followedOnly: true) ??
      _bestLive(events, follows) ??
      _bestUpcoming(events, follows, now);
  return hero;
}

/// Live events, optionally restricted to followed ones.
List<SportsEvent> _liveEvents(
  List<SportsEvent> events,
  SportsFollows follows, {
  bool followedOnly = false,
}) => events
    .where(
      (event) =>
          event.status == SportsEventStatus.live &&
          (!followedOnly || follows.followsEvent(event)),
    )
    .toList();

SportsEvent? _bestLive(
  List<SportsEvent> events,
  SportsFollows follows, {
  bool followedOnly = false,
}) => _best(
  _liveEvents(events, follows, followedOnly: followedOnly),
  (a, b) => _byLiveRow(a, b, follows),
);

SportsEvent? _bestUpcoming(
  List<SportsEvent> events,
  SportsFollows follows,
  DateTime now,
) {
  final horizon = now.add(_twentyFourHours);
  return _best(
    events.where(
      (event) =>
          event.status == SportsEventStatus.scheduled &&
          follows.followsEvent(event) &&
          !event.start.isBefore(now) &&
          !event.start.isAfter(horizon),
    ),
    _byStartAsc,
  );
}

SportsBoardSection? _live(
  List<SportsEvent> events,
  SportsFollows follows, {
  bool followedOnly = false,
}) => _row(
  id: 'live',
  title: 'Live now',
  section: _liveEvents(events, follows, followedOnly: followedOnly),
  compare: (a, b) => _byLiveRow(a, b, follows),
);

/// Followed, live or scheduled, starting before [now] + 7 days; the today
/// filter narrows that to the current local day.
SportsBoardSection? _yourTeams(
  List<SportsEvent> events,
  SportsFollows follows,
  DateTime now, {
  bool todayOnly = false,
}) => _row(
  id: 'your-teams',
  title: 'Your teams',
  section: events.where(
    (event) =>
        follows.followsEvent(event) &&
        (event.status == SportsEventStatus.live ||
            event.status == SportsEventStatus.scheduled) &&
        event.start.isBefore(now.add(_oneWeek)) &&
        (!todayOnly || _isSameLocalDay(event.start, now)),
  ),
  compare: _byStartAsc,
);

SportsBoardSection? _laterToday(List<SportsEvent> events, DateTime now) => _row(
  id: 'later-today',
  title: 'Later today',
  section: events.where(
    (event) =>
        event.status == SportsEventStatus.scheduled &&
        event.start.isAfter(now) &&
        _isSameLocalDay(event.start, now),
  ),
  compare: _byStartAsc,
);

/// Scheduled fixtures on local days one through six.
SportsBoardSection? _thisWeek(List<SportsEvent> events, DateTime now) => _row(
  id: 'this-week',
  title: 'This week',
  section: events.where(
    (event) =>
        event.status == SportsEventStatus.scheduled &&
        _localDayOffset(event.start, now) >= 1 &&
        _localDayOffset(event.start, now) <= 6,
  ),
  compare: _byStartAsc,
);

SportsBoardSection? _earlierToday(List<SportsEvent> events, DateTime now) =>
    _row(
      id: 'earlier-today',
      title: 'Earlier today',
      section: events.where(
        (event) =>
            event.status == SportsEventStatus.finished &&
            _isSameLocalDay(event.start, now),
      ),
      compare: _byStartDesc,
    );

SportsBoardSection? _upcoming(
  List<SportsEvent> events,
  SportsFollows follows,
  DateTime now,
) => _row(
  id: 'upcoming',
  title: 'Upcoming',
  section: events.where(
    (event) =>
        follows.followsEvent(event) &&
        event.status == SportsEventStatus.scheduled &&
        event.start.isAfter(now) &&
        event.start.isBefore(now.add(_oneWeek)),
  ),
  compare: _byStartAsc,
);

/// Followed results from the last two days.
SportsBoardSection? _recentResults(
  List<SportsEvent> events,
  SportsFollows follows,
  DateTime now,
) => _row(
  id: 'recent',
  title: 'Recent results',
  section: events.where(
    (event) =>
        follows.followsEvent(event) &&
        event.status == SportsEventStatus.finished &&
        event.start.isAfter(now.subtract(_oneDay * 2)),
  ),
  compare: _byStartDesc,
);

/// A sorted row, or null when nothing qualifies.
SportsBoardSection? _row({
  required String id,
  required String title,
  required Iterable<SportsEvent> section,
  required int Function(SportsEvent a, SportsEvent b) compare,
}) {
  final events = section.toList()..sort(compare);
  if (events.isEmpty) return null;
  return SportsBoardSection(id: id, title: title, events: events);
}

SportsEvent? _best(
  Iterable<SportsEvent> candidates,
  int Function(SportsEvent a, SportsEvent b) compare,
) {
  SportsEvent? best;
  for (final candidate in candidates) {
    if (best == null || compare(candidate, best) < 0) best = candidate;
  }
  return best;
}

/// Followed first, then league importance descending, then start ascending.
int _byLiveRow(SportsEvent a, SportsEvent b, SportsFollows follows) {
  final byFollow = (follows.followsEvent(b) ? 1 : 0).compareTo(
    follows.followsEvent(a) ? 1 : 0,
  );
  if (byFollow != 0) return byFollow;
  final byImportance = sportsLeagueImportance(
    b.leagueId,
  ).compareTo(sportsLeagueImportance(a.leagueId));
  if (byImportance != 0) return byImportance;
  return _byStartAsc(a, b);
}

int _byStartAsc(SportsEvent a, SportsEvent b) {
  final byStart = a.start.compareTo(b.start);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}

int _byStartDesc(SportsEvent a, SportsEvent b) => -_byStartAsc(a, b);

bool _isSameLocalDay(DateTime a, DateTime b) => _localDayOffset(a, b) == 0;

/// Whole local calendar days between [instant] and [reference].
///
/// Compare local day starts pinned to UTC rather than subtracting instants:
/// a DST day is 23 or 25 hours, so `difference(...).inDays` on local values
/// truncates to the wrong count.
int _localDayOffset(DateTime instant, DateTime reference) =>
    _localDayStart(instant).difference(_localDayStart(reference)).inDays;

DateTime _localDayStart(DateTime instant) {
  final local = instant.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}
