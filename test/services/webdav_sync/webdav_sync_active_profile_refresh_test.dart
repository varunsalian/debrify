import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_ui_refresh.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_active_profile_refresh.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/stremio_service.dart';

void main() {
  const refresher = DefaultWebDavSyncActiveProfileRefresher();

  TestWidgetsFlutterBinding.ensureInitialized();

  test('synced hide-watched is refreshed before Home is notified', () async {
    SharedPreferences.setMockInitialValues({});
    HideWatchedPrefs.debugReset();
    await HideWatchedPrefs.warmUp();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HideWatchedPrefs.key, true);
    expect(HideWatchedPrefs.enabled, isFalse);
    final observed = <bool>[];
    void listener() => observed.add(HideWatchedPrefs.enabled);
    MainPageBridge.addHomeSettingsListener(listener);
    addTearDown(() {
      MainPageBridge.removeHomeSettingsListener(listener);
      HideWatchedPrefs.debugReset();
    });
    await refresher.refresh({
      HideWatchedPrefs.key,
    }, authorizationBarrier: () {});
    WebDavSyncUiRefresh.dispatch({HideWatchedPrefs.key});
    expect(observed, [true]);
    await prefs.remove(HideWatchedPrefs.key);
    await refresher.refresh({
      HideWatchedPrefs.key,
    }, authorizationBarrier: () {});
    WebDavSyncUiRefresh.dispatch({HideWatchedPrefs.key});
    expect(observed, [true, false]);
  });

  test(
    'profile switch during hide-watched read prevents cache publication',
    () async {
      SharedPreferences.setMockInitialValues({HideWatchedPrefs.key: true});
      HideWatchedPrefs.debugReset();
      var barriers = 0;
      await expectLater(
        refresher.refresh(
          {HideWatchedPrefs.key},
          authorizationBarrier: () {
            if (++barriers == 2) throw StateError('profile switched');
          },
        ),
        throwsStateError,
      );
      expect(HideWatchedPrefs.enabled, isFalse);
    },
  );

  test('unrelated keys and stale sessions cannot notify addon views', () async {
    var calls = 0;
    void listener() => calls++;
    StremioService.instance.addAddonsChangedListener(listener);
    addTearDown(
      () => StremioService.instance.removeAddonsChangedListener(listener),
    );
    await refresher.refresh({'unrelated_key'}, authorizationBarrier: () {});
    expect(calls, 0);
    await expectLater(
      refresher.refresh({
        'stremio_addons_v1',
      }, authorizationBarrier: () => throw StateError('profile switched')),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test('one stale addon listener cannot block another mounted view', () async {
    var calls = 0;
    void stale() => throw StateError('disposed view');
    void mounted() => calls++;
    StremioService.instance.addAddonsChangedListener(stale);
    StremioService.instance.addAddonsChangedListener(mounted);
    addTearDown(() {
      StremioService.instance.removeAddonsChangedListener(stale);
      StremioService.instance.removeAddonsChangedListener(mounted);
    });
    await refresher.refresh({'stremio_addons_v1'}, authorizationBarrier: () {});
    expect(calls, 1);
  });

  test('playlist refresh is awaited and authorization-bracketed', () async {
    final events = <String>[];
    Future<void> playlistListener() async {
      events.add('playlist-start');
      await Future<void>.delayed(Duration.zero);
      events.add('playlist-end');
    }

    MainPageBridge.addPlaylistChangeListener(playlistListener);

    try {
      await refresher.refresh(const <String>{
        WebDavSyncHotMerge.playlistPreference,
      }, authorizationBarrier: () => events.add('barrier'));
    } finally {
      MainPageBridge.removePlaylistChangeListener(playlistListener);
    }

    expect(events, <String>[
      'barrier',
      'playlist-start',
      'playlist-end',
      'barrier',
    ]);
  });

  test('synced completion publishes its process revision', () async {
    final completionBefore = StorageService.localCompletionRevision.value;

    await refresher.refresh(const <String>{
      WebDavSyncHotMerge.playbackPreference,
    }, authorizationBarrier: () {});

    expect(StorageService.localCompletionRevision.value, completionBefore + 1);
  });

  test('profile switch during an awaited refresh is detected', () async {
    var authorized = true;
    Future<void> playlistListener() async {
      authorized = false;
    }

    MainPageBridge.addPlaylistChangeListener(playlistListener);
    addTearDown(
      () => MainPageBridge.removePlaylistChangeListener(playlistListener),
    );

    await expectLater(
      refresher.refresh(
        const <String>{WebDavSyncHotMerge.playlistPreference},
        authorizationBarrier: () {
          if (!authorized) throw StateError('profile switched');
        },
      ),
      throwsStateError,
    );
  });
}
