import 'dart:convert';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'dart:async';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  testWidgets(
    'Resume P14 provider playlist shrink preserves the out of range launch key fallback',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      final a = source(
        'P14.Bounds.Show.S01E02.mkv',
        'https://player.test/p14-bounds-a2.mp4',
      );
      final b = source(
        'P14.Bounds.Show.S01E02.mkv',
        'https://player.test/p14-bounds-b2.mp4',
      );
      final incoming = [
        const PlaylistEntry(
          url: 'https://player.test/p14-bounds-b1.mp4',
          title: 'P14.Bounds.Show.S01E01.mkv',
        ),
        PlaylistEntry(url: b.directUrl!, title: b.name),
      ];
      final originalIncoming = List<PlaylistEntry>.of(incoming);
      final errors = <Object>[];
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      try {
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P14 bounds show',
            playlist: [
              const PlaylistEntry(
                url: 'https://player.test/p14-bounds-a1.mp4',
                title: 'P14.Bounds.Show.S01E01.mkv',
              ),
              PlaylistEntry(url: a.directUrl!, title: a.name),
            ],
            startIndex: 1,
            disableAutoResume: true,
            contentType: 'series',
            stremioSources: [a, b],
            stremioCurrentSourceIndex: 0,
            resolveStremioSource: (s) async => s.directUrl,
            resolveSourceToPlaylist: (s, {canContinue}) async => incoming,
          ),
        );
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(t, sheet.resolveSource(b)))!;
        final callback = sheet.onSourceSelected as dynamic;
        final selected = f.actions.start('replace borrowed playlist', () async {
          final result = callback(1, url);
          if (result is Future) await result;
        });
        await f.finish(t, selected.future);
        await f.actions.settle(t);
        expect(f.player.state.playlist.medias.first.uri, b.directUrl);
        final menu = await display.menu(PlayerMenuSection.speed);
        final enhancedBefore = jsonDecode(
          jsonEncode(
            await f.finish(t, PlaybackStateStore.getPlaybackStateMap()),
          ),
        );
        incoming.removeLast();
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        checkpoints = 0;
        runZoned(
          () => menu.onSpeedSelected(1.5),
          zoneSpecification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stack) =>
                errors.add(error),
          ),
        );
        await f.until(t, () => errors.isNotEmpty || checkpoints > 0);
        expect(errors, isEmpty);
        expect(checkpoints, 1);
        final saved = await f.finish(
          t,
          VideoResumeStorage.getVideoResume(a.directUrl!),
        );
        expect(saved?['positionMs'], 300000);
        expect(saved?['speed'], 1.5);
        expect(
          await f.finish(t, PlaybackStateStore.getPlaybackStateMap()),
          enhancedBefore,
          reason:
              'An invalid current index skips enhanced series persistence and preserves the old episode map',
        );
      } finally {
        incoming
          ..clear()
          ..addAll(originalIncoming);
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
      }
    },
  );
}
