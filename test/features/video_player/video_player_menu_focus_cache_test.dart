import 'dart:async';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/subtitle_sources_driver.dart';

void main() {
  testWidgets(
    'p13 TV tracks Back leaves pane then closes and restores player focus',
    (t) async {
      final d = SubtitleSourcesDriver(t);
      await d.setup();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/focus.mp4',
            title: 'TV focus',
            contentImdbId: 'tt1300001',
            contentType: 'movie',
          ),
        );
        t.widget<TvControls>(find.byType(TvControls)).onShowTracks();
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsOneWidget);
        await d.f.key(t, LogicalKeyboardKey.arrowRight);
        await d.f.key(t, LogicalKeyboardKey.escape);
        expect(
          find.byType(PlayerMenuPanel),
          findsOneWidget,
          reason: 'first Back consumes pane navigation',
        );
        await d.f.key(t, LogicalKeyboardKey.escape);
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsNothing);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets(
    'p13 panel discovery completion after close writes the open identity cache',
    (t) async {
      final d = SubtitleSourcesDriver(t);
      await d.setup();
      final gate = Completer<http.Response>();
      try {
        await d.register('p13-cache');
        await d.order();
        d.f.network.handler = (r) => r.url.path.startsWith('/subtitles/')
            ? gate.future
            : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
        // A public widget update supplies an identity after the original no-ID
        // automatic discovery completed. Only the panel owns this later fetch.
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/cache.mp4',
            title: 'Cache close',
          ),
        );
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: d.f.navigator,
            theme: ThemeData.dark(),
            home: const VideoPlayerScreen(
              videoUrl: 'https://player.test/cache.mp4',
              title: 'Cache close',
              contentImdbId: 'tt1300001',
              contentType: 'movie',
            ),
          ),
        );
        await d.f.advance(t);
        final panel = await d.menu();
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.startsWith('/subtitles/'),
          ),
        );
        panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        gate.complete(d.slots('p13-cache'));
        await d.f.actions.settle(t);
        final reopened = await d.menu();
        expect(reopened.cachedAddonSlots, hasLength(1));
        expect(
          reopened.cachedAddonSlots!.single.subtitles.single.id,
          'p13-cache',
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete(http.Response('{}', 404));
        await d.close();
      }
    },
  );
}
