import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday evening, local time: every assertion is relative to this instant
/// and uses local `DateTime` values, so the suite is timezone independent.
final DateTime now = DateTime(2026, 10, 28, 20, 41);

DateTime at(int month, int day, int hour, [int minute = 0]) =>
    DateTime(2026, month, day, hour, minute);

const arsenal = SportsTeam(
  id: 'ars',
  name: 'Arsenal',
  shortName: 'Arsenal',
  abbreviation: 'ARS',
);

const chelsea = SportsTeam(
  id: 'che',
  name: 'Chelsea',
  shortName: 'Chelsea',
  abbreviation: 'CHE',
);

const lakers = SportsTeam(
  id: 'lal',
  name: 'Los Angeles Lakers',
  shortName: 'Lakers',
  abbreviation: 'LAL',
);

SportsEvent ev({
  required String id,
  String leagueId = 'ucl',
  required DateTime start,
  SportsEventStatus status = SportsEventStatus.scheduled,
  SportsTeam? home = arsenal,
  SportsTeam? away = chelsea,
}) => SportsEvent(
  id: id,
  leagueId: leagueId,
  start: start,
  status: status,
  home: home,
  away: away,
);

SportsEvent live({
  required String id,
  String leagueId = 'ucl',
  DateTime? start,
}) => ev(
  id: id,
  leagueId: leagueId,
  start: start ?? at(10, 28, 20, 10),
  status: SportsEventStatus.live,
);

SportsEvent finished({
  required String id,
  String leagueId = 'ucl',
  DateTime? start,
}) => ev(
  id: id,
  leagueId: leagueId,
  start: start ?? at(10, 28, 17),
  status: SportsEventStatus.finished,
);

List<String> ids(List<SportsBoardSection> sections) => [
  for (final section in sections) section.id,
];

List<String> titles(List<SportsBoardSection> sections) => [
  for (final section in sections) section.title,
];

List<String> eventsOf(List<SportsBoardSection> sections, String id) => [
  for (final event in sections.firstWhere((section) => section.id == id).events)
    event.id,
];

bool containsEvent(List<SportsBoardSection> sections, String eventId) =>
    sections.any(
      (section) => section.events.any((event) => event.id == eventId),
    );

const noFollows = SportsFollows();

void main() {
  group('live filter', () {
    test('shows only live fixtures under Live now', () {
      final sections = buildSportsBoardSections(
        events: [
          live(id: 'live-ucl'),
          ev(id: 'scheduled', start: at(10, 28, 22)),
          finished(id: 'finished'),
          ev(
            id: 'postponed',
            start: at(10, 28, 20),
            status: SportsEventStatus.postponed,
          ),
        ],
        follows: noFollows,
        now: now,
        filter: SportsBoardFilter.live,
      );

      expect(ids(sections), ['live']);
      expect(titles(sections), ['Live now']);
      expect(eventsOf(sections, 'live'), ['live-ucl']);
    });

    test('puts followed fixtures first, then importance, then start', () {
      final sections = buildSportsBoardSections(
        events: [
          live(id: 'ucl-late', start: at(10, 28, 20, 30)),
          live(id: 'ucl-early', start: at(10, 28, 19, 30)),
          live(id: 'epl-late', leagueId: 'epl', start: at(10, 28, 20, 35)),
          live(id: 'epl-early', leagueId: 'epl', start: at(10, 28, 20, 20)),
          live(id: 'nba-late', leagueId: 'nba', start: at(10, 28, 18)),
        ],
        follows: const SportsFollows(leagueIds: {'epl'}),
        now: now,
        filter: SportsBoardFilter.live,
      );

      expect(eventsOf(sections, 'live'), [
        'epl-early',
        'epl-late',
        'ucl-early',
        'ucl-late',
        'nba-late',
      ]);
    });

    test('is empty when nothing is live', () {
      final sections = buildSportsBoardSections(
        events: [
          ev(id: 'scheduled', start: at(10, 28, 22)),
          finished(id: 'finished', start: at(10, 28, 17)),
        ],
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
        filter: SportsBoardFilter.live,
      );
      expect(sections, isEmpty);
    });
  });

  group('today filter', () {
    test('orders live, your teams, later today, earlier today', () {
      final sections = buildSportsBoardSections(
        events: [
          live(id: 'live-ucl', start: at(10, 28, 20, 10)),
          ev(id: 'later-late', leagueId: 'epl', start: at(10, 28, 23, 55)),
          ev(id: 'later-soon', leagueId: 'epl', start: at(10, 28, 22)),
          finished(id: 'earlier', leagueId: 'nba', start: at(10, 28, 17)),
        ],
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
        filter: SportsBoardFilter.today,
      );

      expect(ids(sections), [
        'live',
        'your-teams',
        'later-today',
        'earlier-today',
      ]);
      expect(titles(sections), [
        'Live now',
        'Your teams',
        'Later today',
        'Earlier today',
      ]);
      expect(eventsOf(sections, 'live'), ['live-ucl']);
      expect(eventsOf(sections, 'your-teams'), ['live-ucl']);
      expect(eventsOf(sections, 'later-today'), ['later-soon', 'later-late']);
      expect(eventsOf(sections, 'earlier-today'), ['earlier']);
    });

    test('your teams stays on the local day', () {
      final events = [
        live(id: 'live-nba', leagueId: 'nba', start: at(10, 28, 20, 5)),
        ev(id: 'tonight', leagueId: 'nba', start: at(10, 28, 21, 30)),
        ev(id: 'tomorrow', leagueId: 'nba', start: at(10, 29, 15)),
      ];
      const follows = SportsFollows(leagueIds: {'nba'});

      final today = buildSportsBoardSections(
        events: events,
        follows: follows,
        now: now,
        filter: SportsBoardFilter.today,
      );
      expect(ids(today), ['live', 'your-teams', 'later-today']);
      expect(eventsOf(today, 'your-teams'), ['live-nba', 'tonight']);
      expect(containsEvent(today, 'tomorrow'), isFalse);

      final week = buildSportsBoardSections(
        events: events,
        follows: follows,
        now: now,
        filter: SportsBoardFilter.week,
      );
      expect(eventsOf(week, 'your-teams'), ['live-nba', 'tonight', 'tomorrow']);
      expect(eventsOf(week, 'day-1'), ['tomorrow']);
    });

    test('later today takes only scheduled fixtures after now on this day', () {
      final sections = buildSportsBoardSections(
        events: [
          ev(id: 'exactly-now', start: now),
          ev(id: 'after-midnight', start: at(10, 29, 0, 30)),
          ev(id: 'tonight', start: at(10, 28, 23, 55)),
          finished(id: 'finished-late', start: at(10, 28, 23)),
          live(id: 'live-late', start: at(10, 28, 21)),
        ],
        follows: noFollows,
        now: now,
        filter: SportsBoardFilter.today,
      );

      expect(ids(sections), ['live', 'later-today', 'earlier-today']);
      expect(eventsOf(sections, 'later-today'), ['tonight']);
      expect(containsEvent(sections, 'exactly-now'), isFalse);
      expect(containsEvent(sections, 'after-midnight'), isFalse);
    });

    test('earlier today lists finished fixtures of this day newest first', () {
      final sections = buildSportsBoardSections(
        events: [
          finished(id: 'earlier-late', start: at(10, 28, 19)),
          finished(id: 'earlier-early', start: at(10, 28, 12, 30)),
          finished(id: 'yesterday', start: at(10, 27, 23)),
          ev(
            id: 'postponed',
            start: at(10, 28, 18),
            status: SportsEventStatus.postponed,
          ),
        ],
        follows: noFollows,
        now: now,
        filter: SportsBoardFilter.today,
      );

      expect(ids(sections), ['earlier-today']);
      expect(eventsOf(sections, 'earlier-today'), [
        'earlier-late',
        'earlier-early',
      ]);
    });
  });

  group('week filter', () {
    test('one row per local day between later today and earlier today', () {
      final sections = buildSportsBoardSections(
        events: [
          live(id: 'live-ucl', start: at(10, 28, 20, 10)),
          ev(id: 'tonight', leagueId: 'epl', start: at(10, 28, 22)),
          ev(id: 'tomorrow-early', leagueId: 'epl', start: at(10, 29, 0, 30)),
          ev(id: 'tomorrow-late', leagueId: 'nba', start: at(10, 29, 23)),
          ev(id: 'day-six', leagueId: 'epl', start: at(11, 3, 15)),
          ev(id: 'day-seven', leagueId: 'epl', start: at(11, 4, 15)),
          finished(id: 'earlier', leagueId: 'nba', start: at(10, 28, 17)),
          finished(
            id: 'finished-tomorrow',
            leagueId: 'epl',
            start: at(10, 29, 20),
          ),
        ],
        follows: noFollows,
        now: now,
        filter: SportsBoardFilter.week,
      );

      expect(ids(sections), [
        'live',
        'later-today',
        'day-1',
        'day-6',
        'earlier-today',
      ]);
      expect(titles(sections), [
        'Live now',
        'Later today',
        'Tomorrow',
        'Tuesday 3 Nov',
        'Earlier today',
      ]);
      expect(eventsOf(sections, 'later-today'), ['tonight']);
      expect(eventsOf(sections, 'day-1'), ['tomorrow-early', 'tomorrow-late']);
      expect(eventsOf(sections, 'day-6'), ['day-six']);
    });

    test('day rows cover local days one through six only', () {
      final sections = buildSportsBoardSections(
        events: [
          ev(id: 'today', start: at(10, 28, 22)),
          ev(id: 'day-one', start: at(10, 29, 0, 30)),
          ev(id: 'day-three', start: at(10, 31, 12)),
          ev(id: 'day-six', start: at(11, 3, 23, 59)),
          ev(id: 'day-seven', start: at(11, 4, 0, 30)),
        ],
        follows: noFollows,
        now: now,
        filter: SportsBoardFilter.week,
      );

      expect(ids(sections), ['later-today', 'day-1', 'day-3', 'day-6']);
      expect(eventsOf(sections, 'day-1'), ['day-one']);
      expect(eventsOf(sections, 'day-3'), ['day-three']);
      expect(eventsOf(sections, 'day-6'), ['day-six']);
      expect(eventsOf(sections, 'later-today'), ['today']);
      expect(containsEvent(sections, 'day-seven'), isFalse);
    });

    test('your teams reaches the seven-day horizon, the day rows do not', () {
      final sections = buildSportsBoardSections(
        events: [
          ev(id: 'stale-scheduled', start: at(10, 27, 18)),
          ev(id: 'day-seven-morning', start: at(11, 4, 20)),
          ev(id: 'on-the-horizon', start: now.add(const Duration(days: 7))),
        ],
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
        filter: SportsBoardFilter.week,
      );

      expect(ids(sections), ['your-teams']);
      expect(eventsOf(sections, 'your-teams'), [
        'stale-scheduled',
        'day-seven-morning',
      ]);
    });
  });

  group('following only', () {
    test('the week shows followed live, day and recent rows', () {
      final sections = buildSportsBoardSections(
        events: [
          live(id: 'live-followed', start: at(10, 28, 20, 10)),
          live(id: 'live-other', leagueId: 'nba', start: at(10, 28, 20, 20)),
          ev(id: 'soon', start: at(10, 29, 20)),
          ev(id: 'far', start: at(11, 10, 20)),
          finished(id: 'recent-tonight', start: at(10, 28, 18)),
          finished(id: 'recent-two-days', start: at(10, 26, 21)),
          finished(id: 'stale', start: at(10, 25, 20)),
          finished(id: 'recent-other', leagueId: 'nba', start: at(10, 28, 19)),
        ],
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
        filter: SportsBoardFilter.week,
        followingOnly: true,
      );

      // "Your teams" would repeat every row, so it is dropped here.
      expect(ids(sections), ['live', 'day-1', 'recent']);
      expect(titles(sections), ['Live now', 'Tomorrow', 'Recent results']);
      expect(eventsOf(sections, 'live'), ['live-followed']);
      expect(eventsOf(sections, 'day-1'), ['soon']);
      expect(eventsOf(sections, 'recent'), [
        'recent-tonight',
        'recent-two-days',
      ]);
    });

    test('day and recent windows exclude their exact boundaries', () {
      final sections = buildSportsBoardSections(
        events: [
          ev(id: 'at-now', start: now),
          ev(id: 'week-boundary', start: now.add(const Duration(days: 7))),
          ev(id: 'inside-window', start: now.add(const Duration(days: 6))),
          finished(
            id: 'two-days-ago',
            start: now.subtract(const Duration(days: 2)),
          ),
          finished(id: 'inside-recent', start: at(10, 26, 20, 42)),
        ],
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
        filter: SportsBoardFilter.week,
        followingOnly: true,
      );

      expect(ids(sections), ['day-6', 'recent']);
      expect(eventsOf(sections, 'day-6'), ['inside-window']);
      expect(eventsOf(sections, 'recent'), ['inside-recent']);
    });

    test('followed teams qualify without a followed league', () {
      final sections = buildSportsBoardSections(
        events: [
          ev(
            id: 'lakers',
            leagueId: 'nba',
            home: lakers,
            away: arsenal,
            start: at(10, 29, 19),
          ),
          ev(
            id: 'other',
            leagueId: 'nba',
            home: arsenal,
            away: chelsea,
            start: at(10, 29, 20),
          ),
        ],
        follows: const SportsFollows(teamKeys: {'nba:lal'}),
        now: now,
        filter: SportsBoardFilter.week,
        followingOnly: true,
      );

      expect(ids(sections), ['day-1']);
      expect(eventsOf(sections, 'day-1'), ['lakers']);
    });

    test('today and live narrow to followed fixtures too', () {
      final events = [
        live(id: 'live-followed', start: at(10, 28, 20, 10)),
        live(id: 'live-other', leagueId: 'nba', start: at(10, 28, 20, 20)),
        ev(id: 'tonight', start: at(10, 28, 22)),
        ev(id: 'tonight-other', leagueId: 'nba', start: at(10, 28, 22)),
        finished(id: 'earlier', start: at(10, 28, 17)),
        finished(id: 'yesterday', start: at(10, 27, 21)),
      ];
      const follows = SportsFollows(leagueIds: {'ucl'});

      final today = buildSportsBoardSections(
        events: events,
        follows: follows,
        now: now,
        filter: SportsBoardFilter.today,
        followingOnly: true,
      );
      expect(ids(today), ['live', 'later-today', 'earlier-today']);
      expect(eventsOf(today, 'live'), ['live-followed']);
      expect(eventsOf(today, 'later-today'), ['tonight']);
      expect(eventsOf(today, 'earlier-today'), ['earlier']);

      final liveOnly = buildSportsBoardSections(
        events: events,
        follows: follows,
        now: now,
        filter: SportsBoardFilter.live,
        followingOnly: true,
      );
      expect(ids(liveOnly), ['live']);
      expect(eventsOf(liveOnly, 'live'), ['live-followed']);
    });

    test(
      'drops rows that would be empty and yields nothing without follows',
      () {
        final events = [
          live(id: 'live-other', leagueId: 'nba', start: at(10, 28, 20, 10)),
          ev(id: 'tonight-other', leagueId: 'nba', start: at(10, 28, 22)),
          finished(id: 'earlier-other', leagueId: 'nba', start: at(10, 28, 17)),
        ];

        for (final filter in SportsBoardFilter.values) {
          expect(
            buildSportsBoardSections(
              events: events,
              follows: noFollows,
              now: now,
              filter: filter,
              followingOnly: true,
            ),
            isEmpty,
            reason: filter.name,
          );
        }

        final onlyTomorrow = buildSportsBoardSections(
          events: [ev(id: 'soon', start: at(10, 29, 20))],
          follows: const SportsFollows(leagueIds: {'ucl'}),
          now: now,
          filter: SportsBoardFilter.week,
          followingOnly: true,
        );
        expect(ids(onlyTomorrow), ['day-1']);
      },
    );
  });

  group('counts', () {
    final events = [
      live(id: 'live-ucl', start: at(10, 28, 20, 10)),
      ev(id: 'tonight', leagueId: 'epl', start: at(10, 28, 22)),
      ev(id: 'tomorrow', leagueId: 'nba', start: at(10, 29, 19)),
      finished(id: 'earlier', leagueId: 'nba', start: at(10, 28, 17)),
    ];

    test('each When segment counts the distinct fixtures it shows', () {
      // The followed UCL fixture appears in Live and in Your teams but
      // counts once.
      final counts = sportsBoardFilterCounts(
        events: events,
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
      );
      expect(counts, {
        SportsBoardFilter.live: 1,
        SportsBoardFilter.today: 3,
        SportsBoardFilter.week: 4,
      });
    });

    test('following only counts followed fixtures', () {
      final counts = sportsBoardFilterCounts(
        events: events,
        follows: const SportsFollows(leagueIds: {'nba'}),
        now: now,
        followingOnly: true,
      );
      expect(counts, {
        SportsBoardFilter.live: 0,
        SportsBoardFilter.today: 1,
        SportsBoardFilter.week: 2,
      });
    });
  });

  group('section building', () {
    test('every filter is empty for an empty feed', () {
      for (final filter in SportsBoardFilter.values) {
        expect(
          buildSportsBoardSections(
            events: const [],
            follows: const SportsFollows(leagueIds: {'ucl'}),
            now: now,
            filter: filter,
          ),
          isEmpty,
          reason: filter.name,
        );
      }
    });

    test('leaves the input list untouched', () {
      final events = [
        live(id: 'b', start: at(10, 28, 20, 10)),
        ev(id: 'a', start: at(10, 28, 22)),
      ];

      buildSportsBoardSections(
        events: events,
        follows: const SportsFollows(leagueIds: {'ucl'}),
        now: now,
        filter: SportsBoardFilter.week,
      );

      expect(events.map((event) => event.id), ['b', 'a']);
    });
  });

  group('pickSportsHero', () {
    test('a followed live fixture beats a bigger unfollowed one', () {
      final hero = pickSportsHero(
        [
          live(id: 'ucl-live', start: at(10, 28, 19)),
          live(id: 'epl-live', leagueId: 'epl', start: at(10, 28, 20)),
        ],
        const SportsFollows(leagueIds: {'epl'}),
        now,
      );
      expect(hero?.id, 'epl-live');
    });

    test('unfollowed live picks highest importance, then earliest start', () {
      final hero = pickSportsHero(
        [
          live(id: 'nba-live', leagueId: 'nba', start: at(10, 28, 19)),
          live(id: 'ucl-late', start: at(10, 28, 20, 30)),
          live(id: 'ucl-early', start: at(10, 28, 19, 30)),
          live(
            id: 'unknown-league',
            leagueId: 'pickup-basketball',
            start: at(10, 28, 18),
          ),
        ],
        noFollows,
        now,
      );
      expect(hero?.id, 'ucl-early');
    });

    test(
      'with nothing live it takes the earliest followed fixture due soon',
      () {
        final hero = pickSportsHero(
          [
            ev(id: 'far', start: at(10, 30, 10)),
            ev(id: 'later-tonight', start: at(10, 29, 18)),
            ev(id: 'next-up', start: at(10, 28, 21, 30)),
            ev(id: 'unfollowed-soon', leagueId: 'nba', start: at(10, 28, 21)),
          ],
          const SportsFollows(leagueIds: {'ucl'}),
          now,
        );
        expect(hero?.id, 'next-up');
      },
    );

    test('the 24 hour edge still counts as due soon', () {
      final hero = pickSportsHero(
        [ev(id: 'edge', start: now.add(const Duration(hours: 24)))],
        const SportsFollows(leagueIds: {'ucl'}),
        now,
      );
      expect(hero?.id, 'edge');
    });

    test('null when nothing is live and no followed fixture is due soon', () {
      expect(
        pickSportsHero(
          [
            ev(id: 'far', start: at(10, 30, 10)),
            ev(id: 'unfollowed-soon', leagueId: 'nba', start: at(10, 28, 21)),
            finished(id: 'earlier', start: at(10, 28, 17)),
          ],
          const SportsFollows(leagueIds: {'ucl'}),
          now,
        ),
        isNull,
      );
    });

    test('postponed fixtures never headline', () {
      expect(
        pickSportsHero(
          [
            ev(
              id: 'postponed',
              start: at(10, 28, 20),
              status: SportsEventStatus.postponed,
            ),
            ev(id: 'due-later', start: at(10, 30, 10)),
          ],
          const SportsFollows(leagueIds: {'ucl'}),
          now,
        ),
        isNull,
      );
    });

    test('null for an empty feed', () {
      expect(pickSportsHero(const [], const SportsFollows(), now), isNull);
    });
  });
}
