import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'content playback start and stop signals are balanced and idempotent',
    () {
      var starts = 0;
      var stops = 0;
      void onStart() => starts++;
      void onStop() => stops++;
      MainPageBridge.addPlayerLaunchListener(onStart);
      MainPageBridge.addContentPlaybackStopListener(onStop);
      addTearDown(() {
        MainPageBridge.notifyContentPlaybackStopped();
        MainPageBridge.removePlayerLaunchListener(onStart);
        MainPageBridge.removeContentPlaybackStopListener(onStop);
      });

      MainPageBridge.notifyPlayerLaunching(isTrailer: true);
      MainPageBridge.notifyContentPlaybackStopped();
      expect(starts, 0);
      expect(stops, 0);

      MainPageBridge.notifyPlayerLaunching();
      MainPageBridge.notifyPlayerLaunching();
      expect(starts, 2);

      MainPageBridge.notifyContentPlaybackStopped();
      MainPageBridge.notifyContentPlaybackStopped();
      expect(stops, 1);

      MainPageBridge.notifyPlayerLaunching();
      MainPageBridge.notifyPlaybackReturned();
      expect(starts, 3);
      expect(stops, 2);
    },
  );

  test('playlist refresh reaches every mounted consumer', () async {
    var playlistTabRefreshes = 0;
    var homeBoardRefreshes = 0;
    Future<void> refreshPlaylistTab() async => playlistTabRefreshes++;
    Future<void> refreshHomeBoard() async => homeBoardRefreshes++;
    MainPageBridge.addPlaylistChangeListener(refreshPlaylistTab);
    MainPageBridge.addPlaylistChangeListener(refreshHomeBoard);
    addTearDown(() {
      MainPageBridge.removePlaylistChangeListener(refreshPlaylistTab);
      MainPageBridge.removePlaylistChangeListener(refreshHomeBoard);
    });

    await MainPageBridge.notifyPlaylistChanged();

    expect(playlistTabRefreshes, 1);
    expect(homeBoardRefreshes, 1);
  });

  test('a failed playlist consumer does not skip the others', () async {
    var successfulRefreshes = 0;
    Future<void> failing() async => throw StateError('stale widget');
    Future<void> successful() async => successfulRefreshes++;
    MainPageBridge.addPlaylistChangeListener(failing);
    MainPageBridge.addPlaylistChangeListener(successful);
    addTearDown(() {
      MainPageBridge.removePlaylistChangeListener(failing);
      MainPageBridge.removePlaylistChangeListener(successful);
    });

    await MainPageBridge.notifyPlaylistChanged();

    expect(successfulRefreshes, 1);
  });
}
