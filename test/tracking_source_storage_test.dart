import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(ProfileRuntime.debugReset);

  test('absent legacy scrobble switches seed all tracker masters on', () async {
    final targets = await TrackingSourceStorage.getTrackingScrobbleTargets();

    expect(targets, Set<TrackingSource>.of(TrackingSource.values));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(TrackingSourceStorage.trackingScrobbleTargetsKey),
      isNotNull,
    );
  });

  test('legacy values are consulted once when seeding masters', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'trakt_sync_catalog_items': false,
      'mdblist_sync_catalog_items': false,
    });

    expect(
      await TrackingSourceStorage.getTrackingScrobbleTargets(),
      <TrackingSource>{TrackingSource.local, TrackingSource.simkl},
    );

    await TraktStorage.setTraktSyncCatalogItems(true);
    await SimklStorage.setSimklSyncCatalogItems(false);
    await MdblistStorage.setMdblistSyncCatalogItems(true);
    expect(
      await TrackingSourceStorage.getTrackingScrobbleTargets(),
      <TrackingSource>{TrackingSource.local, TrackingSource.simkl},
    );
  });

  test('connecting a tracker re-enables only that scrobble target', () async {
    for (final source in const <TrackingSource>[
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    ]) {
      await TrackingSourceStorage.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });

      await TrackingSourceStorage.enableTrackingScrobbleTarget(source);

      expect(
        await TrackingSourceStorage.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local, source},
      );
    }
  });

  test('re-enabling an active scrobble target is idempotent', () async {
    await TrackingSourceStorage.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
    final revision = TrackingSourceStorage.trackingSourceRevision.value;

    await TrackingSourceStorage.enableTrackingScrobbleTarget(
      TrackingSource.simkl,
    );

    expect(TrackingSourceStorage.trackingSourceRevision.value, revision);
    expect(
      await TrackingSourceStorage.getTrackingScrobbleTargets(),
      <TrackingSource>{TrackingSource.local, TrackingSource.simkl},
    );
  });

  test('re-enabling a tracker preserves other scrobble choices', () async {
    await TrackingSourceStorage.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });

    await TrackingSourceStorage.enableTrackingScrobbleTarget(
      TrackingSource.simkl,
    );

    expect(
      await TrackingSourceStorage.getTrackingScrobbleTargets(),
      <TrackingSource>{
        TrackingSource.local,
        TrackingSource.trakt,
        TrackingSource.simkl,
      },
    );
  });

  test('simultaneous tracker connections merge every target', () async {
    await TrackingSourceStorage.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });

    await Future.wait(<Future<void>>[
      TrackingSourceStorage.enableTrackingScrobbleTarget(TrackingSource.trakt),
      TrackingSourceStorage.enableTrackingScrobbleTarget(TrackingSource.simkl),
      TrackingSourceStorage.enableTrackingScrobbleTarget(
        TrackingSource.mdblist,
      ),
    ]);

    expect(
      await TrackingSourceStorage.getTrackingScrobbleTargets(),
      Set<TrackingSource>.of(TrackingSource.values),
    );
  });

  test(
    'legacy reseed after an old-backup restore re-adopts restored switches',
    () async {
      // App start seeds the masters (all ON) before any restore happens.
      expect(
        await TrackingSourceStorage.getTrackingScrobbleTargets(),
        Set<TrackingSource>.of(TrackingSource.values),
      );

      // An old backup's tracker sections then restore the legacy switches —
      // Trakt/Simkl hardcode ON, MDBList carries its saved value (OFF here).
      await TraktStorage.setTraktSyncCatalogItems(true);
      await SimklStorage.setSimklSyncCatalogItems(true);
      await MdblistStorage.setMdblistSyncCatalogItems(false);

      // Without the reseed the already-seeded masters would ignore that OFF.
      await TrackingSourceStorage.reseedTrackingScrobbleTargetsFromLegacy();
      expect(
        await TrackingSourceStorage.getTrackingScrobbleTargets(),
        <TrackingSource>{
          TrackingSource.local,
          TrackingSource.trakt,
          TrackingSource.simkl,
        },
      );
    },
  );

  test('tracking transfer payload round-trips all three preferences', () async {
    await TrackingSourceStorage.applyTrackingPreferencesPayload(
      <String, dynamic>{
        'scrobble_targets': <String>['trakt'],
        'progress_source': 'trakt',
        'home_tick_sources': <String>['local', 'simkl'],
      },
    );

    final payload =
        await TrackingSourceStorage.buildTrackingPreferencesPayload();
    expect(
      payload['scrobble_targets'],
      containsAll(<String>['local', 'trakt']),
    );
    expect(payload['progress_source'], 'trakt');
    expect(
      payload['home_tick_sources'],
      containsAll(<String>['local', 'simkl']),
    );
  });

  test('a disconnected dedicated progress source falls back visibly', () async {
    await TrackingSourceStorage.setWatchProgressSource(
      WatchProgressSource.trakt,
    );

    final policy = await TrackingSourcePolicy.load();

    expect(policy.progressSource, WatchProgressSource.smart);
    expect(
      await TrackingSourceStorage.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    expect(
      await TrackingSourceStorage.takeTrackingProgressFallbackNotice(),
      isTrue,
    );
    expect(
      await TrackingSourceStorage.takeTrackingProgressFallbackNotice(),
      isFalse,
    );
  });

  test(
    'partial backup restore leaves tracking preferences untouched',
    () async {
      await TrackingSourceStorage.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });
      await TrackingSourceStorage.setWatchProgressSource(
        WatchProgressSource.local,
      );
      await TrackingSourceStorage.setHomeTickSources(<TrackingSource>{
        TrackingSource.local,
      });

      await BackupRestoreService.applyBackup(
        <String, dynamic>{
          'trackingPreferences': <String, dynamic>{
            'scrobble_targets': <String>['local', 'trakt'],
            'progress_source': 'smart',
            'home_tick_sources': <String>['trakt'],
          },
        },
        selection: const BackupSelection(
          realDebrid: false,
          torbox: false,
          premiumize: false,
          allDebrid: false,
          pikpak: false,
          trakt: false,
          simkl: false,
          mdblist: false,
          searchEngines: false,
          addons: false,
          webDav: false,
          indexerManagers: false,
          iptvPlaylists: false,
          iptvFavorites: false,
          iptvLists: false,
        ),
      );

      expect(
        await TrackingSourceStorage.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local},
      );
      expect(
        await TrackingSourceStorage.getWatchProgressSource(),
        WatchProgressSource.local,
      );
      expect(await TrackingSourceStorage.getHomeTickSources(), <TrackingSource>{
        TrackingSource.local,
      });
    },
  );

  test('full backup restore applies tracking preferences', () async {
    await BackupRestoreService.applyBackup(<String, dynamic>{
      'trackingPreferences': <String, dynamic>{
        'scrobble_targets': <String>['local', 'simkl'],
        'progress_source': 'local',
        'home_tick_sources': <String>['mdblist'],
      },
    });

    expect(
      await TrackingSourceStorage.getTrackingScrobbleTargets(),
      <TrackingSource>{TrackingSource.local, TrackingSource.simkl},
    );
    expect(
      await TrackingSourceStorage.getWatchProgressSource(),
      WatchProgressSource.local,
    );
    expect(await TrackingSourceStorage.getHomeTickSources(), <TrackingSource>{
      TrackingSource.mdblist,
    });
  });
}
