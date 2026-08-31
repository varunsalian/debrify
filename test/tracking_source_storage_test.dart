import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
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
    final targets = await StorageService.getTrackingScrobbleTargets();

    expect(targets, Set<TrackingSource>.of(TrackingSource.values));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(StorageService.trackingScrobbleTargetsKey),
      isNotNull,
    );
  });

  test('legacy values are consulted once when seeding masters', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'trakt_sync_catalog_items': false,
      'mdblist_sync_catalog_items': false,
    });

    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });

    await StorageService.setTraktSyncCatalogItems(true);
    await StorageService.setSimklSyncCatalogItems(false);
    await StorageService.setMdblistSyncCatalogItems(true);
    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('connecting a tracker re-enables only that scrobble target', () async {
    for (final source in const <TrackingSource>[
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    ]) {
      await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });

      await StorageService.enableTrackingScrobbleTarget(source);

      expect(
        await StorageService.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local, source},
      );
    }
  });

  test('re-enabling an active scrobble target is idempotent', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
    final revision = StorageService.trackingSourceRevision.value;

    await StorageService.enableTrackingScrobbleTarget(TrackingSource.simkl);

    expect(StorageService.trackingSourceRevision.value, revision);
    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
  });

  test('re-enabling a tracker preserves other scrobble choices', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
    });

    await StorageService.enableTrackingScrobbleTarget(TrackingSource.simkl);

    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.simkl,
    });
  });

  test('simultaneous tracker connections merge every target', () async {
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });

    await Future.wait(<Future<void>>[
      StorageService.enableTrackingScrobbleTarget(TrackingSource.trakt),
      StorageService.enableTrackingScrobbleTarget(TrackingSource.simkl),
      StorageService.enableTrackingScrobbleTarget(TrackingSource.mdblist),
    ]);

    expect(
      await StorageService.getTrackingScrobbleTargets(),
      Set<TrackingSource>.of(TrackingSource.values),
    );
  });

  test(
    'legacy reseed after an old-backup restore re-adopts restored switches',
    () async {
      // App start seeds the masters (all ON) before any restore happens.
      expect(
        await StorageService.getTrackingScrobbleTargets(),
        Set<TrackingSource>.of(TrackingSource.values),
      );

      // An old backup's tracker sections then restore the legacy switches —
      // Trakt/Simkl hardcode ON, MDBList carries its saved value (OFF here).
      await StorageService.setTraktSyncCatalogItems(true);
      await StorageService.setSimklSyncCatalogItems(true);
      await StorageService.setMdblistSyncCatalogItems(false);

      // Without the reseed the already-seeded masters would ignore that OFF.
      await StorageService.reseedTrackingScrobbleTargetsFromLegacy();
      expect(
        await StorageService.getTrackingScrobbleTargets(),
        <TrackingSource>{
          TrackingSource.local,
          TrackingSource.trakt,
          TrackingSource.simkl,
        },
      );
    },
  );

  test('tracking transfer payload round-trips all three preferences', () async {
    await StorageService.applyTrackingPreferencesPayload(<String, dynamic>{
      'scrobble_targets': <String>['trakt'],
      'progress_source': 'trakt',
      'home_tick_sources': <String>['local', 'simkl'],
    });

    final payload = await StorageService.buildTrackingPreferencesPayload();
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
    await StorageService.setWatchProgressSource(WatchProgressSource.trakt);

    final policy = await TrackingSourcePolicy.load();

    expect(policy.progressSource, WatchProgressSource.smart);
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.smart,
    );
    expect(await StorageService.takeTrackingProgressFallbackNotice(), isTrue);
    expect(await StorageService.takeTrackingProgressFallbackNotice(), isFalse);
  });

  test(
    'partial backup restore leaves tracking preferences untouched',
    () async {
      await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
        TrackingSource.local,
      });
      await StorageService.setWatchProgressSource(WatchProgressSource.local);
      await StorageService.setHomeTickSources(<TrackingSource>{
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
        await StorageService.getTrackingScrobbleTargets(),
        <TrackingSource>{TrackingSource.local},
      );
      expect(
        await StorageService.getWatchProgressSource(),
        WatchProgressSource.local,
      );
      expect(await StorageService.getHomeTickSources(), <TrackingSource>{
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

    expect(await StorageService.getTrackingScrobbleTargets(), <TrackingSource>{
      TrackingSource.local,
      TrackingSource.simkl,
    });
    expect(
      await StorageService.getWatchProgressSource(),
      WatchProgressSource.local,
    );
    expect(await StorageService.getHomeTickSources(), <TrackingSource>{
      TrackingSource.mdblist,
    });
  });
}
