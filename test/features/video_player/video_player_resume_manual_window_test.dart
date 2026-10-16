import 'dart:async';
import 'dart:convert';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport, no dependency changes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 manual selection suppresses periodic saves but permits an explicit generic transition checkpoint',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      final old = SharedPreferencesStorePlatform.instance;
      final gate = Completer<void>();
      SleepResumeWrites? store;
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      try {
        await display.defaults();
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/p14-manual-one.mp4',
            title: 'P14 Manual Show',
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/p14-manual-one.mp4',
                title: 'P14.Manual.Show.S01E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/p14-manual-two.mp4',
                title: 'P14.Manual.Show.S01E02.mkv',
              ),
            ],
            contentType: 'series',
          ),
        );
        final menu = await display.menu(PlayerMenuSection.speed);
        await display.closeMenu();
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        f.player.delays['open'] = gate;
        final selection = f.actions.start(
          'manual held open',
          () => browser.onEpisodeSelected(1, 2),
          held: true,
        );
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        expect(selection.isCompleted, isFalse);
        final outgoing = await f.finish(
          t,
          SeriesProgressStorage.getSeriesPlaybackState(
            seriesTitle: browser.seriesPlaylist.seriesTitle!,
            imdbId: browser.seriesPlaylist.imdbId,
            season: 1,
            episode: 1,
          ),
        );
        expect(
          outgoing?['positionMs'],
          300000,
          reason:
              'The old episode is checkpointed before the selected index changes',
        );
        store = await t.runAsync(SleepResumeWrites.install);
        checkpoints = 0;
        await f.advance(t, const Duration(seconds: 12));
        expect(
          store!.writes.where((v) => v.$1.endsWith('playback_state_v1')),
          isEmpty,
        );
        expect(checkpoints, 0);
        menu.onSpeedSelected(1.5);
        await f.until(t, () => checkpoints == 1);
        final writes = store.writes
            .where((v) => v.$1.endsWith('playback_state_v1'))
            .toList();
        expect(writes, hasLength(1));
        final map = jsonDecode(writes.single.$2 as String) as Map;
        expect(
          map.values.whereType<Map>().where((v) => v['type'] == 'series'),
          isNotEmpty,
        );
        final saved = await f.finish(
          t,
          SeriesProgressStorage.getSeriesPlaybackState(
            seriesTitle: browser.seriesPlaylist.seriesTitle!,
            imdbId: browser.seriesPlaylist.imdbId,
            season: 1,
            episode: 2,
          ),
        );
        expect(
          saved?['positionMs'],
          300000,
          reason:
              'The old generic-transition behavior samples the old player position against the already selected episode',
        );
        expect(saved?['speed'], 1.5);
        gate.complete();
        await f.finish(t, selection.future);
        await f.actions.settle(t);
        expect(
          f.player.state.position,
          const Duration(milliseconds: 80),
          reason:
              'The original manual no-resume decision was captured before the in-flight explicit save',
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        final finalWrites = store.writes.length;
        await f.advance(t, const Duration(seconds: 6));
        expect(
          store.writes.length,
          finalWrites,
          reason:
              'The manual no-resume return does not clear manual selection before its existing timer',
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );
}
