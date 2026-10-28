import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

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

const celtics = SportsTeam(
  id: 'bos',
  name: 'Boston Celtics',
  shortName: 'Celtics',
  abbreviation: 'BOS',
);

SportsEvent match({
  String id = 'e1',
  String leagueId = 'ucl',
  SportsTeam? home = arsenal,
  SportsTeam? away = chelsea,
}) => SportsEvent(
  id: id,
  leagueId: leagueId,
  start: DateTime.utc(2026, 10, 28, 20),
  status: SportsEventStatus.scheduled,
  home: home,
  away: away,
);

/// In-memory [SportsPrefs] with the same missing-key semantics as the plugin.
class FakeSportsPrefs implements SportsPrefs {
  final Map<String, List<String>> lists = {};
  final Map<String, bool> bools = {};
  final List<String> writtenKeys = [];

  @override
  List<String>? getStringList(String key) => lists[key];

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    lists[key] = value;
    writtenKeys.add(key);
    return true;
  }

  @override
  bool? getBool(String key) => bools[key];

  @override
  Future<bool> setBool(String key, bool value) async {
    bools[key] = value;
    writtenKeys.add(key);
    return true;
  }
}

void main() {
  late FakeSportsPrefs prefs;
  late SportsFollowStore store;

  setUp(() {
    prefs = FakeSportsPrefs();
    store = SportsFollowStore(() async => prefs);
  });

  group('SportsFollows', () {
    test('a followed league covers every fixture in it', () {
      const follows = SportsFollows(leagueIds: {'ucl'});
      expect(follows.followsEvent(match()), isTrue);
      expect(follows.followsEvent(match(leagueId: 'nba')), isFalse);
    });

    test('a followed team key covers fixtures where it is home or away', () {
      const follows = SportsFollows(teamKeys: {'ucl:che'});
      expect(follows.followsEvent(match()), isTrue, reason: 'away side');
      expect(
        follows.followsEvent(match(home: chelsea, away: lakers)),
        isTrue,
        reason: 'home side',
      );
      expect(follows.followsEvent(match(home: lakers, away: celtics)), isFalse);
    });

    test('team keys stay scoped to their league', () {
      const follows = SportsFollows(teamKeys: {'nba:che'});
      expect(follows.followsEvent(match()), isFalse);
      expect(follows.followsEvent(match(leagueId: 'nba')), isTrue);
    });

    test('an event without competitors only answers to its league', () {
      final grandPrix = match(id: 'gp', leagueId: 'f1', home: null, away: null);
      expect(
        const SportsFollows(leagueIds: {'f1'}).followsEvent(grandPrix),
        isTrue,
      );
      expect(
        const SportsFollows(teamKeys: {'f1:1'}).followsEvent(grandPrix),
        isFalse,
        reason: 'a team key cannot match a side that does not exist',
      );
      expect(
        const SportsFollows(
          teamKeys: {'ucl:ars'},
        ).followsEvent(match(away: null)),
        isTrue,
        reason: 'a one-sided fixture still matches its known side',
      );
    });

    test('nothing is followed by default', () {
      const follows = SportsFollows();
      expect(follows.leagueIds, isEmpty);
      expect(follows.teamKeys, isEmpty);
      expect(follows.hideScores, isFalse);
      expect(follows.followsEvent(match()), isFalse);
    });

    test('copyWith replaces only what it is given', () {
      const original = SportsFollows(
        leagueIds: {'ucl'},
        teamKeys: {'ucl:ars'},
        hideScores: true,
      );
      expect(
        original.copyWith(hideScores: false),
        const SportsFollows(
          leagueIds: {'ucl'},
          teamKeys: {'ucl:ars'},
          hideScores: false,
        ),
      );
      expect(
        original.copyWith(leagueIds: {'nba'}, teamKeys: {'nba:lal'}),
        const SportsFollows(
          leagueIds: {'nba'},
          teamKeys: {'nba:lal'},
          hideScores: true,
        ),
      );
      expect(original.copyWith(), original);
      expect(
        original.copyWith(leagueIds: const {}, teamKeys: const {}),
        const SportsFollows(hideScores: true),
      );
    });

    test('equality and hashing ignore set insertion order', () {
      const a = SportsFollows(leagueIds: {'ucl', 'nba'}, teamKeys: {'ucl:ars'});
      const b = SportsFollows(leagueIds: {'nba', 'ucl'}, teamKeys: {'ucl:ars'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(hideScores: true)));
      expect(a, isNot(const SportsFollows(leagueIds: {'ucl'})));
      expect(
        a.hashCode,
        isNot(
          const SportsFollows(
            leagueIds: {'ucl'},
            teamKeys: {'ucl:ars'},
          ).hashCode,
        ),
      );
    });
  });

  group('SportsFollowStore', () {
    test('exposes stable keys', () {
      expect(SportsFollowStore.leaguesKey, 'sports_followed_leagues');
      expect(SportsFollowStore.teamsKey, 'sports_followed_teams');
      expect(SportsFollowStore.hideScoresKey, 'sports_hide_scores');
    });

    test('missing keys read back as follows-nothing', () async {
      expect(await store.read(), const SportsFollows());
      expect(prefs.writtenKeys, isEmpty, reason: 'read must not write');
    });

    test('reads stored lists and flag', () async {
      prefs.lists[SportsFollowStore.leaguesKey] = ['epl', 'ucl'];
      prefs.lists[SportsFollowStore.teamsKey] = ['ucl:ars'];
      prefs.bools[SportsFollowStore.hideScoresKey] = true;
      expect(
        await store.read(),
        const SportsFollows(
          leagueIds: {'epl', 'ucl'},
          teamKeys: {'ucl:ars'},
          hideScores: true,
        ),
      );
    });

    test('writes lists sorted ascending and the hide-scores flag', () async {
      await store.write(
        const SportsFollows(
          leagueIds: {'ucl', 'epl', 'nba'},
          teamKeys: {'ucl:che', 'nba:lal'},
          hideScores: true,
        ),
      );
      expect(prefs.lists[SportsFollowStore.leaguesKey], ['epl', 'nba', 'ucl']);
      expect(prefs.lists[SportsFollowStore.teamsKey], ['nba:lal', 'ucl:che']);
      expect(prefs.bools[SportsFollowStore.hideScoresKey], isTrue);
      expect(prefs.writtenKeys, [
        SportsFollowStore.leaguesKey,
        SportsFollowStore.teamsKey,
        SportsFollowStore.hideScoresKey,
      ]);
    });

    test(
      'an empty follow list is stored as an empty list, not skipped',
      () async {
        await store.write(const SportsFollows());
        expect(prefs.lists[SportsFollowStore.leaguesKey], isEmpty);
        expect(prefs.lists[SportsFollowStore.teamsKey], isEmpty);
        expect(prefs.bools[SportsFollowStore.hideScoresKey], isFalse);
      },
    );

    test('write then read round-trips, including clearing', () async {
      final follows = const SportsFollows(
        leagueIds: {'ucl'},
        teamKeys: {'ucl:ars'},
        hideScores: true,
      );
      await store.write(follows);
      expect(await store.read(), follows);
      await store.write(const SportsFollows());
      expect(await store.read(), const SportsFollows());
    });

    test(
      'storage is resolved per operation, so a profile switch is picked up',
      () async {
        final next = FakeSportsPrefs();
        next.lists[SportsFollowStore.leaguesKey] = ['nba'];
        var active = prefs;
        final switching = SportsFollowStore(() async => active);

        expect(await switching.read(), const SportsFollows());
        active = next;
        expect(await switching.read(), const SportsFollows(leagueIds: {'nba'}));

        await switching.write(const SportsFollows(teamKeys: {'nba:lal'}));
        expect(next.lists[SportsFollowStore.teamsKey], ['nba:lal']);
        expect(prefs.lists[SportsFollowStore.teamsKey], isNull);
        expect(prefs.writtenKeys, isEmpty);
      },
    );
  });
}
