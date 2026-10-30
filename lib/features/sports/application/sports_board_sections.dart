// Turns a flat event list into the ordered rows the board renders.
//
// Application layer: pure functions over immutable models — no fetching, no
// persistence, no UI. Each base list owns its eligibility rule and its sort;
// the active [SportsBoardFilter] only decides which lists appear, in which
// order, and empty lists are dropped so the view never renders a blank row.
// Following narrows any of the three views to followed fixtures.
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// The board's time windows, one per segment of the When switch.
enum SportsBoardFilter { live, today, week }

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
const int _weekDays = 6;
const Duration _oneWeek = Duration(days: 7);

/// The rows for [filter], in display order, omitting empty ones.
///
/// "Today" and the week's day rows are local calendar days of [now], never
/// UTC days, so a 23:00 UTC fixture lands on the day the user sees. With
/// [followingOnly] every row keeps only followed fixtures, "Your teams" is
/// dropped as redundant, and the week ends with the last two days' results
/// instead of today's.
List<SportsBoardSection> buildSportsBoardSections({
  required List<SportsEvent> events,
  required SportsFollows follows,
  required DateTime now,
  required SportsBoardFilter filter,
  bool followingOnly = false,
}) {
  final pool = followingOnly
      ? events.where(follows.followsEvent).toList()
      : events;
  final sections = switch (filter) {
    SportsBoardFilter.live => [_live(pool, follows)],
    SportsBoardFilter.today => [
      _live(pool, follows),
      if (!followingOnly) _yourTeams(pool, follows, now, todayOnly: true),
      _laterToday(pool, now),
      _earlierToday(pool, now),
    ],
    SportsBoardFilter.week => [
      _live(pool, follows),
      if (!followingOnly) _yourTeams(pool, follows, now),
      _laterToday(pool, now),
      for (var offset = 1; offset <= _weekDays; offset++)
        _day(pool, now, offset),
      followingOnly ? _recentResults(pool, now) : _earlierToday(pool, now),
    ],
  };
  return [
    for (final section in sections)
      if (section != null) section,
  ];
}

/// Distinct fixtures across [sections] ("Your teams" repeats some).
int sportsBoardEventCount(List<SportsBoardSection> sections) => {
  for (final section in sections)
    for (final event in section.events) '${event.leagueId}/${event.id}',
}.length;

/// How many fixtures each When segment would show, for its count badge.
Map<SportsBoardFilter, int> sportsBoardFilterCounts({
  required List<SportsEvent> events,
  required SportsFollows follows,
  required DateTime now,
  bool followingOnly = false,
}) => {
  for (final filter in SportsBoardFilter.values)
    filter: sportsBoardEventCount(
      buildSportsBoardSections(
        events: events,
        follows: follows,
        now: now,
        filter: filter,
        followingOnly: followingOnly,
      ),
    ),
};

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

SportsBoardSection? _live(List<SportsEvent> events, SportsFollows follows) =>
    _row(
      id: 'live',
      title: 'Live now',
      section: _liveEvents(events, follows),
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

/// Scheduled fixtures on the local day [offset] days after [now]'s, titled
/// "Tomorrow" or by the weekday and date.
SportsBoardSection? _day(List<SportsEvent> events, DateTime now, int offset) {
  final local = now.toLocal();
  final day = DateTime(local.year, local.month, local.day + offset);
  return _row(
    id: 'day-$offset',
    title: offset == 1 ? 'Tomorrow' : DateFormat('EEEE d MMM').format(day),
    section: events.where(
      (event) =>
          event.status == SportsEventStatus.scheduled &&
          _localDayOffset(event.start, now) == offset,
    ),
    compare: _byStartAsc,
  );
}

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

/// Results from the last two days (the following view's closing row).
SportsBoardSection? _recentResults(List<SportsEvent> events, DateTime now) =>
    _row(
      id: 'recent',
      title: 'Recent results',
      section: events.where(
        (event) =>
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
