import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/episode_tracker_snapshot_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With Ledger's feature flag off (the build value) stored, defaulted and
/// transferred tracking preferences match the app before Ledger, even when a
/// dev build left Ledger values behind.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() {
    debugLedgerEnabled = null;
    ProfileRuntime.debugReset();
  });

  final beforeLedger = Set<TrackingSource>.of(TrackingSource.values)
    ..remove(TrackingSource.ledger);

  test('default watched ticks leave Ledger out', () async {
    expect(await TrackingSourceStorage.getHomeTickSources(), beforeLedger);
    debugLedgerEnabled = true;
    expect(
      await TrackingSourceStorage.getHomeTickSources(),
      contains(TrackingSource.ledger),
    );
  });

  test('saved ticks never store Ledger', () async {
    await TrackingSourceStorage.setHomeTickSources({
      TrackingSource.trakt,
      TrackingSource.ledger,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(TrackingSourceStorage.homeTickSourcesKey), [
      'trakt',
    ]);
  });

  test('a dev build\'s stored Ledger values read as unknown', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TrackingSourceStorage.watchProgressSourceKey: 'ledger',
      TrackingSourceStorage.homeTickSourcesKey: ['trakt', 'ledger'],
    });
    expect(
      await TrackingSourceStorage.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    expect(await TrackingSourceStorage.getHomeTickSources(), {
      TrackingSource.trakt,
    });
  });

  test('scrobble targets neither read nor store Ledger', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TrackingSourceStorage.trackingScrobbleTargetsKey: [
        'local',
        'trakt',
        'ledger',
      ],
    });
    expect(await TrackingSourceStorage.getTrackingScrobbleTargets(), {
      TrackingSource.local,
      TrackingSource.trakt,
    });
    await TrackingSourceStorage.setTrackingScrobbleTargets({
      TrackingSource.simkl,
      TrackingSource.ledger,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(TrackingSourceStorage.trackingScrobbleTargetsKey),
      ['local', 'simkl'],
    );
  });

  test('Home reads a stored Ledger progress source as Smart', () async {
    await TrackingSourceStorage.setWatchProgressSource(
      WatchProgressSource.ledger,
    );
    expect(
      await TrackingSourceStorage.getEffectiveWatchProgressSource(),
      WatchProgressSource.smart,
    );
  });

  test('transfers neither carry nor apply Ledger values', () async {
    await TrackingSourceStorage.setWatchProgressSource(
      WatchProgressSource.trakt,
    );
    await TrackingSourceStorage.applyTrackingPreferencesPayload({
      'scrobble_targets': ['local', 'trakt', 'ledger'],
      'progress_source': 'ledger',
      'home_tick_sources': ['simkl', 'ledger'],
    });
    expect(
      await TrackingSourceStorage.getWatchProgressSource(),
      WatchProgressSource.trakt,
      reason: 'an unknown progress source keeps the stored choice',
    );
    final payload =
        await TrackingSourceStorage.buildTrackingPreferencesPayload();
    expect(payload['scrobble_targets'], isNot(contains('ledger')));
    expect(payload['home_tick_sources'], ['simkl']);
    expect(payload['progress_source'], 'trakt');
  });

  test('a series reset writes no Ledger snapshot', () async {
    await SeriesProgressStorage.clearSeriesWatchProgress('tt0944947', 'Show');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) => key.contains('ledger')), isEmpty);
  });

  test('a Ledger snapshot refresh is a no-op', () async {
    expect(
      await EpisodeTrackerSnapshotService.refreshLedger('tt0944947'),
      isNull,
    );
  });
}
