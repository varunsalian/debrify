import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MemoryPrefs implements SportsPrefs {
  final Map<String, Object> values = {};
  int writes = 0;

  @override
  List<String>? getStringList(String key) => values[key] as List<String>?;
  @override
  Future<bool> setStringList(String key, List<String> value) async {
    writes++;
    values[key] = List.of(value);
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }
}

SportsLeague _l(String id) => sportsLeagueById(id)!;

void main() {
  group('SportsLeagueFilter', () {
    test('defaults apply when nothing is chosen', () {
      const f = SportsLeagueFilter();
      expect(f.isEnabled(_l('epl')), isTrue);
      expect(f.isEnabled(_l('ncaaf')), isFalse);
    });

    test('off wins over on, then on, then the default', () {
      expect(
        const SportsLeagueFilter(off: {'epl'}).isEnabled(_l('epl')),
        isFalse,
      );
      expect(
        const SportsLeagueFilter(on: {'ncaaf'}).isEnabled(_l('ncaaf')),
        isTrue,
      );
      expect(
        const SportsLeagueFilter(
          on: {'epl'},
          off: {'epl'},
        ).isEnabled(_l('epl')),
        isFalse,
      );
    });

    test('choices equal to the default are not stored', () {
      var f = const SportsLeagueFilter();
      f = f.withLeague(_l('epl'), false);
      expect(f, const SportsLeagueFilter(off: {'epl'}));
      f = f.withLeague(_l('epl'), true);
      expect(f, const SportsLeagueFilter());
      f = f.withLeague(_l('ncaaf'), true);
      expect(f, const SportsLeagueFilter(on: {'ncaaf'}));
      f = f.withLeague(_l('ncaaf'), false);
      expect(f, const SportsLeagueFilter());
    });

    test('switching one league keeps every other choice', () {
      var f = const SportsLeagueFilter();
      f = f.withLeague(_l('epl'), false);
      f = f.withLeague(_l('ncaaf'), true);
      f = f.withLeague(_l('ucl'), false);
      f = f.withLeague(_l('wnba'), true);
      expect(
        f,
        const SportsLeagueFilter(off: {'epl', 'ucl'}, on: {'ncaaf', 'wnba'}),
      );
    });

    test('equal filters hash equally regardless of insertion order', () {
      expect(
        SportsLeagueFilter(on: {'a', 'b'}, off: {'c', 'd'}).hashCode,
        SportsLeagueFilter(on: {'b', 'a'}, off: {'d', 'c'}).hashCode,
      );
    });

    test('value equality', () {
      expect(
        const SportsLeagueFilter(on: {'a'}, off: {'b'}),
        SportsLeagueFilter(on: {'a'}, off: {'b'}),
      );
      expect(
        const SportsLeagueFilter(on: {'a'}).hashCode,
        SportsLeagueFilter(on: {'a'}).hashCode,
      );
      expect(
        const SportsLeagueFilter(on: {'a'}) ==
            const SportsLeagueFilter(off: {'a'}),
        isFalse,
      );
    });

    test('enabledSportsLeagues keeps catalog order', () {
      final enabled = enabledSportsLeagues(
        kSportsLeagues,
        const SportsLeagueFilter(off: {'ucl'}, on: {'ncaaf'}),
      );
      expect(enabled.first.id, 'epl');
      expect(enabled.map((l) => l.id), contains('ncaaf'));
      expect(enabled.map((l) => l.id), isNot(contains('wnba')));
      final order = [for (final l in kSportsLeagues) l.id];
      final positions = [for (final l in enabled) order.indexOf(l.id)];
      expect(positions, [...positions]..sort());
    });
  });

  group('SportsLeagueFilterStore', () {
    test('missing keys read as the empty filter', () async {
      final store = SportsLeagueFilterStore(() async => _MemoryPrefs());
      expect(await store.read(), const SportsLeagueFilter());
    });

    test('round trip with sorted lists under the documented keys', () async {
      final prefs = _MemoryPrefs();
      final store = SportsLeagueFilterStore(() async => prefs);
      await store.write(
        const SportsLeagueFilter(on: {'wnba', 'ncaaf'}, off: {'ucl'}),
      );
      expect(SportsLeagueFilterStore.onKey, 'sports_leagues_on_v1');
      expect(SportsLeagueFilterStore.offKey, 'sports_leagues_off_v1');
      expect(prefs.values['sports_leagues_on_v1'], ['ncaaf', 'wnba']);
      expect(prefs.values['sports_leagues_off_v1'], ['ucl']);
      expect(
        await store.read(),
        const SportsLeagueFilter(on: {'wnba', 'ncaaf'}, off: {'ucl'}),
      );
    });

    test('prefs are resolved per operation (profile switches)', () async {
      var current = _MemoryPrefs();
      final first = current;
      final store = SportsLeagueFilterStore(() async => current);
      await store.write(const SportsLeagueFilter(off: {'ucl'}));
      current = _MemoryPrefs();
      expect(await store.read(), const SportsLeagueFilter());
      expect(first.values['sports_leagues_off_v1'], ['ucl']);
    });
  });

  group('notifier and providers', () {
    late _MemoryPrefs prefs;
    late ProviderContainer container;
    late Object owner;
    late ChangeNotifier profileChanges;

    setUp(() {
      prefs = _MemoryPrefs();
      owner = 'profile-a';
      profileChanges = ChangeNotifier();
      container = ProviderContainer(
        overrides: [
          sportsLeagueFilterStoreProvider.overrideWithValue(
            SportsLeagueFilterStore(() async => prefs),
          ),
          sportsProfileOwnerProvider.overrideWithValue(() => owner),
          sportsProfileChangesProvider.overrideWithValue(profileChanges),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      profileChanges.dispose();
    });

    test('loads the stored filter', () async {
      prefs.values['sports_leagues_off_v1'] = ['epl'];
      expect(
        await container.read(sportsLeagueFilterProvider.future),
        const SportsLeagueFilter(off: {'epl'}),
      );
    });

    test('setLeague updates state and storage', () async {
      await container.read(sportsLeagueFilterProvider.future);
      await container
          .read(sportsLeagueFilterProvider.notifier)
          .setLeague(_l('ncaaf'), true);
      expect(
        container.read(sportsLeagueFilterProvider).value,
        const SportsLeagueFilter(on: {'ncaaf'}),
      );
      expect(prefs.values['sports_leagues_on_v1'], ['ncaaf']);
    });

    test('setSport switches every league of the sport', () async {
      await container.read(sportsLeagueFilterProvider.future);
      await container
          .read(sportsLeagueFilterProvider.notifier)
          .setSport(SportKind.cricket, false);
      final filter = container.read(sportsLeagueFilterProvider).value!;
      for (final l in kSportsLeagues.where(
        (l) => l.sport == SportKind.cricket,
      )) {
        expect(filter.isEnabled(l), isFalse, reason: l.id);
      }
      expect(filter.isEnabled(_l('epl')), isTrue);
      await container
          .read(sportsLeagueFilterProvider.notifier)
          .setSport(SportKind.cricket, true);
      final after = container.read(sportsLeagueFilterProvider).value!;
      for (final l in kSportsLeagues.where(
        (l) => l.sport == SportKind.cricket,
      )) {
        expect(after.isEnabled(l), isTrue, reason: l.id);
      }
    });

    test('reset clears every choice', () async {
      prefs.values['sports_leagues_off_v1'] = ['epl'];
      await container.read(sportsLeagueFilterProvider.future);
      await container.read(sportsLeagueFilterProvider.notifier).reset();
      expect(
        container.read(sportsLeagueFilterProvider).value,
        const SportsLeagueFilter(),
      );
      expect(prefs.values['sports_leagues_off_v1'], isEmpty);
    });

    test('the board leagues follow the filter', () async {
      final defaults = container.read(sportsLeaguesProvider);
      expect(defaults.map((l) => l.id), contains('epl'));
      expect(defaults.map((l) => l.id), isNot(contains('ncaaf')));
      await container.read(sportsLeagueFilterProvider.future);
      await container
          .read(sportsLeagueFilterProvider.notifier)
          .setLeague(_l('epl'), false);
      final after = container.read(sportsLeaguesProvider);
      expect(after.map((l) => l.id), isNot(contains('epl')));
    });
    test('a profile switch reloads the new profile\'s filter', () async {
      prefs.values['sports_leagues_off_v1'] = ['epl'];
      await container.read(sportsLeagueFilterProvider.future);
      final b = _MemoryPrefs()..values['sports_leagues_on_v1'] = ['ncaaf'];
      prefs = b;
      owner = 'profile-b';
      profileChanges.notifyListeners();
      expect(
        await container.read(sportsLeagueFilterProvider.future),
        const SportsLeagueFilter(on: {'ncaaf'}),
      );
    });

    test(
      'a write from a stale profile never reaches the new profile',
      () async {
        await container.read(sportsLeagueFilterProvider.future);
        final notifier = container.read(sportsLeagueFilterProvider.notifier);
        final a = prefs;
        prefs = _MemoryPrefs();
        owner = 'profile-b'; // switched, change not yet delivered
        await notifier.setLeague(_l('epl'), false);
        expect(prefs.writes, 0);
        expect(a.writes, 0);
      },
    );

    test('rapid toggles are written in order', () async {
      await container.read(sportsLeagueFilterProvider.future);
      final notifier = container.read(sportsLeagueFilterProvider.notifier);
      await Future.wait([
        notifier.setLeague(_l('epl'), false),
        notifier.setLeague(_l('ucl'), false),
        notifier.setLeague(_l('ncaaf'), true),
      ]);
      expect(prefs.values['sports_leagues_off_v1'], ['epl', 'ucl']);
      expect(prefs.values['sports_leagues_on_v1'], ['ncaaf']);
      expect(
        container.read(sportsLeagueFilterProvider).value,
        const SportsLeagueFilter(off: {'epl', 'ucl'}, on: {'ncaaf'}),
      );
    });

    test('defaults: no owner and no change signal outside the app', () {
      final plain = ProviderContainer(
        overrides: [
          sportsLeagueFilterStoreProvider.overrideWithValue(
            SportsLeagueFilterStore(() async => _MemoryPrefs()),
          ),
        ],
      );
      addTearDown(plain.dispose);
      expect(plain.read(sportsProfileOwnerProvider)(), isNull);
      expect(plain.read(sportsProfileChangesProvider), isNull);
    });
  });
}
