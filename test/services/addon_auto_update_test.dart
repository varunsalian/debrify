// The once-a-day addon refresh pass: due rule, enable switch, permission,
// last-run bookkeeping, saving only changed addons, and profile switches.
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/addon_auto_update.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StremioAddon _addon(String id, String version, {bool readOnly = false}) =>
    StremioAddon(
      id: id,
      name: 'Addon $id',
      manifestUrl: 'https://$id.test/manifest.json',
      baseUrl: 'https://$id.test',
      version: version,
      connectionResourceReadOnly: readOnly,
    );

class _Fake {
  _Fake(this.installed, this.remote);
  final List<StremioAddon> installed;
  final Map<String, String>
  remote; // manifestUrl → remote version; missing = fetch fails
  bool allowed = true;
  bool current = true;
  final fetched = <String>[];
  final refreshed = <String>[];
  bool refreshReturnsNull = false;
  int? lastRunSeenAtList;

  AddonAutoUpdateDeps deps() => AddonAutoUpdateDeps(
    allowed: () async => allowed,
    listAddons: () async {
      final prefs = await ProfilePreferences.instance();
      lastRunSeenAtList = prefs.getInt(AddonAutoUpdate.lastRunKey);
      return installed;
    },
    fetchManifest: (url) async {
      fetched.add(url);
      final version = remote[url];
      if (version == null) throw StateError('offline');
      final old = installed.firstWhere((a) => a.manifestUrl == url);
      return _addon(old.id, version);
    },
    refreshAddon: (url) async {
      refreshed.add(url);
      return refreshReturnsNull ? null : _addon('x', '9');
    },
    stillCurrent: () => current,
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 30, 12);
  int ms(DateTime t) => t.millisecondsSinceEpoch;

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  group('isDue', () {
    test('never run is due', () {
      expect(AddonAutoUpdate.isDue(lastRunMs: null, now: now), isTrue);
    });
    test('due exactly one interval later, not before', () {
      final last = now.subtract(AddonAutoUpdate.interval);
      expect(AddonAutoUpdate.isDue(lastRunMs: ms(last), now: now), isTrue);
      expect(
        AddonAutoUpdate.isDue(
          lastRunMs: ms(last.add(const Duration(minutes: 1))),
          now: now,
        ),
        isFalse,
      );
    });
    test('a last run far in the future (clock moved back) is due', () {
      final future = now.add(const Duration(hours: 25));
      expect(AddonAutoUpdate.isDue(lastRunMs: ms(future), now: now), isTrue);
      final slightly = now.add(const Duration(hours: 2));
      expect(AddonAutoUpdate.isDue(lastRunMs: ms(slightly), now: now), isFalse);
    });
  });

  test('enabled by default and switchable', () async {
    expect(await AddonAutoUpdate.isEnabled(), isTrue);
    await AddonAutoUpdate.setEnabled(false);
    expect(await AddonAutoUpdate.isEnabled(), isFalse);
  });

  test(
    'refreshes only addons whose version changed, after recording the time',
    () async {
      final fake = _Fake(
        [_addon('a', '1'), _addon('b', '1'), _addon('c', '1', readOnly: true)],
        {
          'https://a.test/manifest.json': '1',
          'https://b.test/manifest.json': '2',
          'https://c.test/manifest.json': '5',
        },
      );
      final outcome = await AddonAutoUpdate.runIfDue(
        now: () => now,
        deps: fake.deps(),
      );
      expect(outcome, AddonAutoUpdateOutcome.updated);
      expect(fake.lastRunSeenAtList, ms(now), reason: 'time is stored first');
      expect(fake.fetched, [
        'https://a.test/manifest.json',
        'https://b.test/manifest.json',
      ], reason: 'shared read-only addons are not ours to update');
      expect(fake.refreshed, ['https://b.test/manifest.json']);
    },
  );

  test('nothing changed saves nothing', () async {
    final fake = _Fake(
      [_addon('a', '1')],
      {'https://a.test/manifest.json': '1'},
    );
    final outcome = await AddonAutoUpdate.runIfDue(
      now: () => now,
      deps: fake.deps(),
    );
    expect(outcome, AddonAutoUpdateOutcome.unchanged);
    expect(fake.refreshed, isEmpty);
  });

  test('offline: failed, and the next try waits a full interval', () async {
    final fake = _Fake([_addon('a', '1'), _addon('b', '1')], {});
    expect(
      await AddonAutoUpdate.runIfDue(now: () => now, deps: fake.deps()),
      AddonAutoUpdateOutcome.failed,
    );
    expect(
      fake.fetched,
      hasLength(2),
      reason: 'one failure does not stop the loop',
    );
    expect(
      await AddonAutoUpdate.runIfDue(
        now: () => now.add(const Duration(hours: 1)),
        deps: fake.deps(),
      ),
      AddonAutoUpdateOutcome.notDue,
    );
  });

  test('a refresh that returns null counts as a failure', () async {
    final fake = _Fake(
      [_addon('a', '1')],
      {'https://a.test/manifest.json': '2'},
    )..refreshReturnsNull = true;
    expect(
      await AddonAutoUpdate.runIfDue(now: () => now, deps: fake.deps()),
      AddonAutoUpdateOutcome.failed,
    );
  });

  test('disabled, or a profile without addon rights, writes nothing', () async {
    final fake = _Fake(
      [_addon('a', '1')],
      {'https://a.test/manifest.json': '2'},
    );
    await AddonAutoUpdate.setEnabled(false);
    expect(
      await AddonAutoUpdate.runIfDue(now: () => now, deps: fake.deps()),
      AddonAutoUpdateOutcome.disabled,
    );
    await AddonAutoUpdate.setEnabled(true);
    fake.allowed = false;
    expect(
      await AddonAutoUpdate.runIfDue(now: () => now, deps: fake.deps()),
      AddonAutoUpdateOutcome.disabled,
    );
    final prefs = await ProfilePreferences.instance();
    expect(prefs.getInt(AddonAutoUpdate.lastRunKey), isNull);
    expect(fake.fetched, isEmpty);
  });

  test('a pass that is not due does not fetch', () async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      AddonAutoUpdate.lastRunKey,
      ms(now.subtract(const Duration(hours: 3))),
    );
    final fake = _Fake(
      [_addon('a', '1')],
      {'https://a.test/manifest.json': '2'},
    );
    expect(
      await AddonAutoUpdate.runIfDue(now: () => now, deps: fake.deps()),
      AddonAutoUpdateOutcome.notDue,
    );
    expect(fake.fetched, isEmpty);
  });

  test('a profile switch mid-pass stops before the next addon', () async {
    final fake = _Fake(
      [_addon('a', '1'), _addon('b', '1')],
      {
        'https://a.test/manifest.json': '2',
        'https://b.test/manifest.json': '2',
      },
    );
    final deps = fake.deps();
    final switching = AddonAutoUpdateDeps(
      allowed: deps.allowed,
      listAddons: deps.listAddons,
      fetchManifest: deps.fetchManifest,
      refreshAddon: (url) async {
        final result = await deps.refreshAddon(url);
        fake.current = false;
        return result;
      },
      stillCurrent: deps.stillCurrent,
    );
    expect(
      await AddonAutoUpdate.runIfDue(now: () => now, deps: switching),
      AddonAutoUpdateOutcome.cancelled,
    );
    expect(fake.refreshed, ['https://a.test/manifest.json']);
  });
}
