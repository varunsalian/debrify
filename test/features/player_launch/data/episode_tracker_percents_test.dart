import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/player_launch/data/episode_tracker_percents.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/ledger_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrackingSourcePolicy _policy(WatchProgressSource progress) =>
    TrackingSourcePolicy(
      scrobbleTargets: const {TrackingSource.local},
      progressSource: progress,
      homeTickSources: const {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Ledger is behind a feature flag (off in builds).
  tearDown(() => debugLedgerEnabled = null);
  setUp(() async {
    debugLedgerEnabled = true;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
      imdbId: 'tt1',
      percents: {'1_1': 40, '1_2': 10},
    );
    await TrackerEpisodeProgressStorage.saveEpisodeSimklProgress(
      imdbId: 'tt1',
      percents: {'1_1': 60},
    );
    // Ledger's snapshot is only read while Ledger is connected.
    await LedgerStorage.setSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiryMs: null,
    );
    await TrackerEpisodeProgressStorage.saveEpisodeLedgerProgress(
      imdbId: 'tt1',
      percents: {'1_1': 80, '1_3': 100},
    );
  });
  tearDown(ProfileRuntime.debugReset);

  test('a stored Ledger snapshot is unused while Ledger is off', () async {
    debugLedgerEnabled = null;
    final percents = EpisodeTrackerPercents.of(
      await EpisodeTrackerPercents.read('tt1'),
    );
    expect(percents.furthest(_policy(WatchProgressSource.smart), '1_1'), 60);
  });

  test('smart takes the furthest tracker, Ledger included', () async {
    final percents = EpisodeTrackerPercents.of(
      await EpisodeTrackerPercents.read('tt1'),
    );
    final smart = _policy(WatchProgressSource.smart);
    expect(percents.furthest(smart, '1_1'), 80);
    expect(percents.furthest(smart, '1_2'), 10);
    expect(percents.furthest(smart, '1_3'), 100);
    expect(percents.furthest(smart, '9_9'), isNull);
    expect(percents.furthest(smart, null), isNull);
    final guide = percents.guide(smart, '1_1');
    expect(
      (guide.trakt, guide.simkl, guide.mdblist, guide.ledger),
      (40, 60, null, 80),
    );
  });

  test('a dedicated progress source masks every other tracker', () async {
    final percents = EpisodeTrackerPercents.of(
      await EpisodeTrackerPercents.read('tt1'),
    );
    expect(percents.furthest(_policy(WatchProgressSource.trakt), '1_1'), 40);
    expect(
      percents.furthest(_policy(WatchProgressSource.ledger), '1_2'),
      isNull,
    );
    expect(
      percents.furthest(_policy(WatchProgressSource.local), '1_1'),
      isNull,
    );
  });

  test('a disconnected Ledger contributes nothing', () async {
    await LedgerStorage.clearAuth();
    final percents = EpisodeTrackerPercents.of(
      await EpisodeTrackerPercents.read('tt1'),
    );
    expect(
      percents.guide(_policy(WatchProgressSource.smart), '1_3').ledger,
      isNull,
    );
    expect(percents.furthest(_policy(WatchProgressSource.smart), '1_1'), 60);
  });

  test('no show id has nothing to merge', () {
    expect(
      EpisodeTrackerPercents.empty.furthest(
        _policy(WatchProgressSource.smart),
        '1_1',
      ),
      isNull,
    );
  });

  test('Ledger\'s snapshot is read only while Ledger is on', () async {
    expect(await EpisodeTrackerPercents.read('tt1'), hasLength(4));
    debugLedgerEnabled = null;
    expect(
      await EpisodeTrackerPercents.read('tt1'),
      hasLength(3),
      reason: 'the same three reads as before Ledger',
    );
  });
}
