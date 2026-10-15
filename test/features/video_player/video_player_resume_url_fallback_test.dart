import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  for (final shape in [
    'live stream',
    'entry',
    'widget',
    'empty',
    'single widget',
    'single empty',
    'single live',
  ]) {
    testWidgets('Resume P14 saved URL uses $shape at the public checkpoint', (
      t,
    ) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      const a = 'https://player.test/p14-url-a.mp4';
      const b = 'https://player.test/p14-url-b.mp4';
      final sources = [source('A', a), source('Pack', b)];
      final entries = [
        const PlaylistEntry(url: a, title: 'P14 URL A'),
        const PlaylistEntry(url: '', title: 'P14 URL B'),
      ];
      VideoPlayerScreen screen(String url) => VideoPlayerScreen(
        videoUrl: url,
        title: 'P14 URL',
        playlist: entries,
        startIndex: 0,
        disableAutoResume: true,
        stremioSources: sources,
        stremioCurrentSourceIndex: 0,
        resolveStremioSource: (s) async => s.directUrl,
        resolveSourceToPlaylist: (s, {canContinue}) async => entries,
      );
      try {
        await f.mount(t, screen(a));
        // Initial Widget playlists are copied. The public provider result is
        // borrowed, so use that real boundary before changing the list.
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final resolved = (await f.finish(t, sheet.resolveSource(sources[1])))!;
        final selected = f.actions.start('borrow provider playlist', () async {
          final dynamic callback = sheet.onSourceSelected;
          final result = callback(1, resolved);
          if (result is Future) await result;
        });
        await f.finish(t, selected.future);
        await f.actions.settle(t);
        await f.finish(t, PlaybackStateStore.savePlaybackStateMap({}));
        final owner = t.state(find.byType(VideoPlayerScreen));
        entries[0] = PlaylistEntry(
          url: shape == 'live stream'
              ? b
              : shape == 'entry'
              ? a
              : '',
          title: 'P14 URL A',
        );
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: screen(shape.endsWith('empty') ? '' : b),
          ),
        );
        expect(t.state(find.byType(VideoPlayerScreen)), same(owner));
        if (shape != 'live stream' && shape != 'single live') {
          final dynamic next = playerControls(t).onNext;
          await f.finish(t, next() as Future<void>);
          await f.actions.settle(t);
          expect(
            find.text(
              'Failed to prepare video: No URL metadata available for this entry',
            ),
            findsOneWidget,
          );
        }
        if (shape.startsWith('single')) entries.clear();
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        final menu = await DisplayModeDriver(
          t,
          f,
        ).menu(PlayerMenuSection.speed);
        menu.onSpeedSelected(1.5);
        await f.actions.settle(t);
        final map = await f.finish(t, PlaybackStateStore.getPlaybackStateMap());
        final rows = map.values
            .whereType<Map>()
            .where((v) => v['type'] == 'video')
            .toList();
        expect(rows, hasLength(1));
        expect(rows.single['positionMs'], 300000);
        expect(rows.single['url'], switch (shape) {
          'live stream' || 'entry' || 'single live' => a,
          'widget' || 'single widget' => b,
          _ => '',
        });
      } finally {
        await f.close(t);
      }
    });
  }
}
