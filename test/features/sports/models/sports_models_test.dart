import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

const home = SportsTeam(
  id: 'team-1',
  name: 'Arsenal',
  shortName: 'Arsenal',
  abbreviation: 'ARS',
  logoUrl: 'https://logos/ars.png',
  color: 0xFFEF0107,
);

const away = SportsTeam(
  id: 'team-2',
  name: 'Bayern München',
  shortName: 'Bayern',
  abbreviation: 'FCB',
);

SportsEvent teamEvent({
  String id = 'e1',
  String leagueId = 'ucl',
  DateTime? start,
  SportsEventStatus status = SportsEventStatus.scheduled,
  SportsTeam? homeTeam = home,
  SportsTeam? awayTeam = away,
  int? homeScore,
  int? awayScore,
  String? title,
  String? subtitle,
  String? clock,
  String statusLabel = '',
  List<String> broadcasts = const [],
}) {
  return SportsEvent(
    id: id,
    leagueId: leagueId,
    start: start ?? DateTime.utc(2026, 10, 28, 20),
    status: status,
    home: homeTeam,
    away: awayTeam,
    homeScore: homeScore,
    awayScore: awayScore,
    title: title,
    subtitle: subtitle,
    clock: clock,
    statusLabel: statusLabel,
    broadcasts: broadcasts,
  );
}

const channelA = SportsChannelRef(name: 'TNT Sports 1', url: 'http://a');
const channelB = SportsChannelRef(name: 'TNT Sports 1 4K', url: 'http://b');

void main() {
  group('SportsLeague equality', () {
    test('uses id only', () {
      const a = SportsLeague(
        id: 'ucl',
        name: 'Champions League',
        shortName: 'UCL',
        sport: SportKind.soccer,
        espnPath: 'soccer/uefa.champions',
        importance: 100,
      );
      const b = SportsLeague(
        id: 'ucl',
        name: 'Totally different',
        shortName: 'XXX',
        sport: SportKind.hockey,
        espnPath: null,
        importance: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(
        a,
        isNot(
          equals(
            const SportsLeague(
              id: 'epl',
              name: 'Champions League',
              shortName: 'UCL',
              sport: SportKind.soccer,
            ),
          ),
        ),
      );
      expect(a, isNot(equals('ucl')));
    });
  });

  group('SportsTeam', () {
    test('value equality over all fields', () {
      const copy = SportsTeam(
        id: 'team-1',
        name: 'Arsenal',
        shortName: 'Arsenal',
        abbreviation: 'ARS',
        logoUrl: 'https://logos/ars.png',
        color: 0xFFEF0107,
      );
      expect(home, equals(copy));
      expect(home.hashCode, equals(copy.hashCode));
      expect(home != away, isTrue);
      expect(
        home,
        isNot(
          equals(
            const SportsTeam(
              id: 'team-1',
              name: 'Arsenal',
              shortName: 'Arsenal',
              abbreviation: 'ARS',
              logoUrl: 'https://logos/ars.png',
              color: 0xFF00FF00,
            ),
          ),
        ),
      );
      expect(
        home,
        isNot(
          equals(
            const SportsTeam(
              id: 'team-1',
              name: 'Arsenal',
              shortName: 'Arsenal',
              abbreviation: 'ARS',
            ),
          ),
        ),
      );
    });

    test('keyIn scopes the team id to a league', () {
      expect(home.keyIn('ucl'), 'ucl:team-1');
      expect(away.keyIn('epl'), 'epl:team-2');
    });
  });

  group('SportsEvent', () {
    test('isTeamEvent and displayTitle', () {
      expect(teamEvent().isTeamEvent, isTrue);
      expect(teamEvent().displayTitle, 'Arsenal v Bayern München');
      final race = teamEvent(
        homeTeam: null,
        awayTeam: null,
        title: 'Mexico City Grand Prix',
        subtitle: 'Autódromo Hermanos Rodríguez',
      );
      expect(race.isTeamEvent, isFalse);
      expect(race.displayTitle, 'Mexico City Grand Prix');
    });

    test('involvesTeam matches league-scoped keys of either side', () {
      final event = teamEvent();
      expect(event.involvesTeam('ucl:team-1'), isTrue);
      expect(event.involvesTeam('ucl:team-2'), isTrue);
      expect(event.involvesTeam('epl:team-1'), isFalse);
      expect(event.involvesTeam('ucl:team-3'), isFalse);
      final race = teamEvent(homeTeam: null, awayTeam: null, title: 'Race');
      expect(race.involvesTeam('ucl:team-1'), isFalse);
    });

    test('value equality covers every field including broadcasts', () {
      final a = teamEvent(
        status: SportsEventStatus.live,
        homeScore: 1,
        awayScore: 0,
        clock: "41'",
        broadcasts: const ['TNT Sports', 'ESPN 2'],
      );
      final b = teamEvent(
        status: SportsEventStatus.live,
        homeScore: 1,
        awayScore: 0,
        clock: "41'",
        broadcasts: const ['TNT Sports', 'ESPN 2'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final reordered = teamEvent(
        status: SportsEventStatus.live,
        homeScore: 1,
        awayScore: 0,
        clock: "41'",
        broadcasts: const ['ESPN 2', 'TNT Sports'],
      );
      expect(a, isNot(equals(reordered)));

      expect(teamEvent(), isNot(equals(teamEvent(statusLabel: 'FT'))));
      expect(
        teamEvent(),
        isNot(equals(teamEvent(subtitle: 'Emirates Stadium'))),
      );
      expect(teamEvent(), isNot(equals(teamEvent(leagueId: 'epl'))));
      expect(
        teamEvent(),
        isNot(equals(teamEvent(start: DateTime.utc(2026, 11, 1)))),
      );
      expect(teamEvent(), isNot(equals(teamEvent(homeTeam: null))));
      expect(teamEvent(), isNot(equals(teamEvent(awayScore: 3))));
      expect(teamEvent(), isNot(equals(teamEvent(id: 'other'))));
      expect(teamEvent(), isNot(equals(teamEvent(title: 'x'))));
      expect(teamEvent(), isNot(equals(teamEvent(clock: "90'"))));
      expect(teamEvent(), isNot(equals('e1')));
    });

    test('defaults are empty label and no broadcasts', () {
      final event = teamEvent();
      expect(event.statusLabel, '');
      expect(event.broadcasts, isEmpty);
      expect(event.title, isNull);
      expect(event.subtitle, isNull);
      expect(event.clock, isNull);
      expect(event.homeScore, isNull);
      expect(event.awayScore, isNull);
    });
  });

  group('SportsChannelRef equality', () {
    test('uses url and playlistId only', () {
      const a = SportsChannelRef(
        name: 'TNT Sports 1',
        url: 'http://a',
        logoUrl: 'logo',
        group: 'Sports',
        attributes: {'tvg-id': 'tnt'},
        httpHeaders: {'Cookie': 'x'},
      );
      const b = SportsChannelRef(
        name: 'TNT Sports 1 4K',
        url: 'http://a',
        group: 'Other',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(channelB)));
      const sameUrlOtherPlaylist = SportsChannelRef(
        name: 'TNT Sports 1',
        url: 'http://a',
        playlistId: 'p2',
      );
      expect(a, isNot(equals(sameUrlOtherPlaylist)));
      expect(a, isNot(equals('http://a')));
    });
  });

  group('SportsGuideListing', () {
    final start = DateTime.utc(2026, 10, 28, 19, 30);
    final stop = DateTime.utc(2026, 10, 28, 22, 15);
    final listing = SportsGuideListing(
      channel: channelA,
      title: 'Live UEFA Champions League: Arsenal v Bayern',
      start: start,
      stop: stop,
    );

    test('airsAt is inclusive of start and exclusive of stop', () {
      expect(listing.airsAt(start), isTrue);
      expect(listing.airsAt(DateTime.utc(2026, 10, 28, 20)), isTrue);
      expect(listing.airsAt(stop.subtract(const Duration(seconds: 1))), isTrue);
      expect(listing.airsAt(stop), isFalse);
      expect(
        listing.airsAt(start.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('value equality over all fields', () {
      expect(
        listing,
        equals(
          SportsGuideListing(
            channel: channelA,
            title: 'Live UEFA Champions League: Arsenal v Bayern',
            start: start,
            stop: stop,
          ),
        ),
      );
      expect(
        listing.hashCode,
        equals(
          SportsGuideListing(
            channel: channelA,
            title: 'Live UEFA Champions League: Arsenal v Bayern',
            start: start,
            stop: stop,
          ).hashCode,
        ),
      );
      expect(
        listing,
        isNot(
          equals(
            SportsGuideListing(
              channel: channelB,
              title: listing.title,
              start: start,
              stop: stop,
            ),
          ),
        ),
      );
      expect(
        listing,
        isNot(
          equals(
            SportsGuideListing(
              channel: channelA,
              title: 'Other',
              start: start,
              stop: stop,
            ),
          ),
        ),
      );
      expect(
        listing,
        isNot(
          equals(
            SportsGuideListing(
              channel: channelA,
              title: listing.title,
              start: start.add(const Duration(minutes: 1)),
              stop: stop,
            ),
          ),
        ),
      );
      expect(listing, isNot(equals('listing')));
    });
  });

  group('SportsWatchOptions', () {
    test('empty constant is empty with count 0', () {
      expect(SportsWatchOptions.empty.isEmpty, isTrue);
      expect(SportsWatchOptions.empty.count, 0);
      expect(SportsWatchOptions.empty.guide, isEmpty);
      expect(SportsWatchOptions.empty.possible, isEmpty);
    });

    test('count and isEmpty over both lists', () {
      const guideOnly = SportsWatchOptions(
        guide: [
          SportsWatchOption(channel: channelA, kind: SportsMatchKind.guide),
        ],
      );
      expect(guideOnly.isEmpty, isFalse);
      expect(guideOnly.count, 1);

      const mixed = SportsWatchOptions(
        guide: [
          SportsWatchOption(channel: channelA, kind: SportsMatchKind.guide),
        ],
        possible: [
          SportsWatchOption(
            channel: channelB,
            kind: SportsMatchKind.broadcaster,
          ),
        ],
      );
      expect(mixed.count, 2);
      expect(mixed.isEmpty, isFalse);

      const none = SportsWatchOptions(guide: [], possible: []);
      expect(none.isEmpty, isTrue);
      expect(none.count, 0);
    });

    test('watch option keeps kind, listing and variants', () {
      final listing = SportsGuideListing(
        channel: channelB,
        title: 'Match',
        start: DateTime.utc(2026, 10, 28, 19, 30),
        stop: DateTime.utc(2026, 10, 28, 22, 15),
      );
      final option = SportsWatchOption(
        channel: channelB,
        kind: SportsMatchKind.guide,
        listing: listing,
        variants: const [channelA],
      );
      expect(option.kind, SportsMatchKind.guide);
      expect(option.listing, listing);
      expect(option.variants, const [channelA]);
      expect(
        option,
        equals(
          SportsWatchOption(
            channel: channelB,
            kind: SportsMatchKind.guide,
            listing: listing,
            variants: const [channelA],
          ),
        ),
      );
      expect(
        option,
        isNot(
          equals(
            SportsWatchOption(
              channel: channelB,
              kind: SportsMatchKind.guide,
              listing: listing,
            ),
          ),
        ),
      );
    });
  });

  group('league catalog', () {
    test('keeps the original 13 ids first, in order', () {
      expect(kSportsLeagues.take(13).map((l) => l.id).toList(), const [
        'ucl',
        'epl',
        'nfl',
        'nba',
        'f1',
        'laliga',
        'uel',
        'seriea',
        'bundesliga',
        'ligue1',
        'nhl',
        'mlb',
        'mls',
      ]);
    });

    test('names, short names, sports, paths and importance match the spec', () {
      const expected = <String, List<Object?>>{
        'ucl': [
          'Champions League',
          'UCL',
          SportKind.soccer,
          'soccer/uefa.champions',
          100,
        ],
        'epl': ['Premier League', 'EPL', SportKind.soccer, 'soccer/eng.1', 95],
        'nfl': ['NFL', 'NFL', SportKind.americanFootball, 'football/nfl', 90],
        'nba': ['NBA', 'NBA', SportKind.basketball, 'basketball/nba', 88],
        'f1': ['Formula 1', 'F1', SportKind.motorsport, null, 85],
        'laliga': ['LaLiga', 'LaLiga', SportKind.soccer, 'soccer/esp.1', 80],
        'uel': [
          'Europa League',
          'UEL',
          SportKind.soccer,
          'soccer/uefa.europa',
          75,
        ],
        'seriea': ['Serie A', 'Serie A', SportKind.soccer, 'soccer/ita.1', 72],
        'bundesliga': [
          'Bundesliga',
          'Bundesliga',
          SportKind.soccer,
          'soccer/ger.1',
          70,
        ],
        'ligue1': ['Ligue 1', 'Ligue 1', SportKind.soccer, 'soccer/fra.1', 65],
        'nhl': ['NHL', 'NHL', SportKind.hockey, 'hockey/nhl', 60],
        'mlb': ['MLB', 'MLB', SportKind.baseball, 'baseball/mlb', 55],
        'mls': ['MLS', 'MLS', SportKind.soccer, 'soccer/usa.1', 50],
      };
      for (final league in kSportsLeagues.take(13)) {
        final row = expected[league.id];
        expect(row, isNotNull, reason: 'unexpected league ${league.id}');
        expect(league.name, row![0], reason: league.id);
        expect(league.shortName, row[1], reason: league.id);
        expect(league.sport, row[2], reason: league.id);
        expect(league.espnPath, row[3], reason: league.id);
        expect(league.importance, row[4], reason: league.id);
      }
      expect(expected.length, 13);
      for (final league in kSportsLeagues.take(13)) {
        expect(league.enabledByDefault, isTrue, reason: league.id);
      }
    });

    test('every league has a unique id, a feed and a unique ESPN path', () {
      final ids = kSportsLeagues.map((l) => l.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      final paths = [
        for (final l in kSportsLeagues)
          if (l.espnPath != null) l.espnPath!,
      ];
      expect(paths.toSet(), hasLength(paths.length));
      for (final league in kSportsLeagues) {
        final hasFeed =
            league.id == 'f1' ||
            league.espnPath != null ||
            league.discoverSport != null;
        expect(hasFeed, isTrue, reason: league.id);
      }
      expect(sportsLeagueById('intl-cricket')?.discoverSport, 'cricket');
    });

    test('niche leagues start off; headline ones start on', () {
      for (final id in ['intl-cricket', 'ipl', 'isl', 'atp', 'wta', 'ufc']) {
        expect(sportsLeagueById(id)!.enabledByDefault, isTrue, reason: id);
      }
      for (final id in ['ncaam', 'ncaaf', 'wnba', 'spfl', 'lpga', 'top14']) {
        expect(sportsLeagueById(id)!.enabledByDefault, isFalse, reason: id);
      }
    });

    test('card shape follows the sport', () {
      SportsEventShape shape(String id) =>
          sportsEventShapeOf(sportsLeagueById(id)!);
      expect(shape('epl'), SportsEventShape.teams);
      expect(shape('six-nations'), SportsEventShape.teams);
      expect(shape('ipl'), SportsEventShape.innings);
      expect(shape('atp'), SportsEventShape.sets);
      expect(shape('ufc'), SportsEventShape.card);
      expect(shape('pga'), SportsEventShape.event);
      expect(shape('f1'), SportsEventShape.event);
    });

    test('sportsLeagueById finds leagues and returns null when unknown', () {
      expect(sportsLeagueById('f1')?.name, 'Formula 1');
      expect(sportsLeagueById('f1')?.espnPath, isNull);
      expect(sportsLeagueById('ucl')?.importance, 100);
      expect(sportsLeagueById('unknown'), isNull);
      expect(sportsLeagueById(''), isNull);
    });

    test('sportsLeagueImportance is 0 when unknown', () {
      expect(sportsLeagueImportance('nba'), 88);
      expect(sportsLeagueImportance('nope'), 0);
    });
  });

  group('guide contract', () {
    test('query defaults are empty needle lists', () {
      final query = SportsGuideQuery(
        fromUtc: DateTime.utc(2026, 10, 28),
        toUtc: DateTime.utc(2026, 10, 29),
        nowUtc: DateTime.utc(2026, 10, 28, 12),
      );
      expect(query.titleNeedles, isEmpty);
      expect(query.channelNeedles, isEmpty);
      expect(
        query,
        equals(
          SportsGuideQuery(
            fromUtc: DateTime.utc(2026, 10, 28),
            toUtc: DateTime.utc(2026, 10, 29),
            nowUtc: DateTime.utc(2026, 10, 28, 12),
          ),
        ),
      );
      expect(
        query,
        isNot(
          equals(
            SportsGuideQuery(
              fromUtc: DateTime.utc(2026, 10, 28),
              toUtc: DateTime.utc(2026, 10, 29),
              nowUtc: DateTime.utc(2026, 10, 28, 12),
              titleNeedles: const ['arsenal'],
            ),
          ),
        ),
      );
    });

    test('snapshot empty constant and equality', () {
      expect(SportsGuideSnapshot.empty.listings, isEmpty);
      expect(SportsGuideSnapshot.empty.channels, isEmpty);
      expect(SportsGuideSnapshot.empty.liveSportsListings, isEmpty);
      const a = SportsGuideSnapshot(channels: [channelA]);
      const b = SportsGuideSnapshot(channels: [channelA]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(SportsGuideSnapshot.empty)));
      expect(a, isNot(equals(const SportsGuideSnapshot(channels: [channelB]))));
    });

    test('SportsGuideSource is implementable', () async {
      final source = _FakeGuideSource();
      final snapshot = await source.load(
        SportsGuideQuery(
          fromUtc: DateTime.utc(2026, 10, 28),
          toUtc: DateTime.utc(2026, 10, 29),
          nowUtc: DateTime.utc(2026, 10, 28, 12),
        ),
      );
      expect(snapshot, same(SportsGuideSnapshot.empty));
    });
  });
}

class _FakeGuideSource implements SportsGuideSource {
  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async =>
      SportsGuideSnapshot.empty;
}
