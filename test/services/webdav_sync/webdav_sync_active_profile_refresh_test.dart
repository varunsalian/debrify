import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_active_profile_refresh.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const refresher = DefaultWebDavSyncActiveProfileRefresher();

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
