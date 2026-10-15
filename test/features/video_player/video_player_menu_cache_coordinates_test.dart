import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/subtitle_sources_driver.dart';

void main() {
  testWidgets(
    'p13 tracks and quick sections reject a cache from the previous widget identity',
    (t) async {
      final d = SubtitleSourcesDriver(t);
      await d.setup();
      VideoPlayerScreen screen(String id) => VideoPlayerScreen(
        videoUrl: 'https://player.test/cache-identity.mp4',
        title: 'Cache identity',
        contentImdbId: id,
        contentType: 'movie',
      );
      try {
        await d.register('p13-identity-cache');
        await d.order();
        d.f.network.replies[d.endpoint(
          'p13-identity-cache',
          identity: 'tt1100002',
        )] = d.slots(
          'p13-incoming-cache',
        );
        await d.mount(screen: screen('tt1100001'));
        final panel = await d.menu();
        final fetched = await d.f.finish(
          t,
          StremioSubtitleService.instance.fetchSubtitleSlots(
            type: 'movie',
            imdbId: 'tt1100001',
          ),
        );
        expect(fetched.single.subtitles, isNotEmpty);
        panel.onAddonSlotsFetched!(fetched);
        await d.f.actions.settle(t);
        panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final warm = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        expect(warm.cachedAddonSlots, hasLength(1));
        warm.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: d.f.navigator,
            theme: ThemeData.dark(),
            home: screen('tt1100002'),
          ),
        );
        await d.f.advance(t);
        expect(
          d.f.players,
          hasLength(1),
          reason: 'the original State and player are retained',
        );
        final incoming = await d.menu();
        expect(incoming.contentImdbId, 'tt1100002');
        expect(incoming.cachedAddonSlots, isNull);
        incoming.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final quick = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        expect(quick.contentImdbId, 'tt1100002');
        expect(quick.cachedAddonSlots, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final (season, episode) in [(3, 4), (3, null), (null, 4)]) {
    testWidgets(
      'p13 tracks cache with coordinates $season/$episode is reused by a quick section',
      (t) async {
        final d = SubtitleSourcesDriver(t);
        await d.setup();
        const addon = 'p13-coordinate-cache';
        try {
          await d.order();
          d.f.network.replies[d.endpoint(addon, type: 'series')] = d.slots(
            addon,
          );
          d.f.network.replies[d.endpoint(
            addon,
            type: 'series',
            identity: 'tt1100001:3:4',
          )] = d.slots(
            addon,
          );
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/coordinates.mp4',
              title: 'Coordinate cache',
              contentImdbId: 'tt1100001',
              contentType: 'series',
              contentSeason: season,
              contentEpisode: episode,
            ),
          );
          await d.register(addon);
          await d.order();
          final tracks = await d.menu();
          expect(tracks.contentSeason, season);
          expect(tracks.contentEpisode, episode);
          final fetched = await d.f.finish(
            t,
            StremioSubtitleService.instance.fetchSubtitleSlots(
              type: 'series',
              imdbId: 'tt1100001',
              season: season,
              episode: episode,
            ),
          );
          expect(fetched.single.subtitles.single.id, addon);
          tracks.onAddonSlotsFetched!(fetched);
          await d.f.actions.settle(t);
          tracks.onClose();
          await d.f.advance(t, const Duration(milliseconds: 350));
          final requests = d.f.network.requests
              .where((request) => request.url.path.startsWith('/subtitles/'))
              .length;
          playerControls(t).onSpeed();
          await d.f.advance(t, const Duration(milliseconds: 350));
          final quick = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
          expect(quick.cachedAddonSlots, isNotNull);
          expect(quick.cachedAddonSlots, hasLength(1));
          expect(quick.cachedAddonSlots!.single.subtitles.single.id, addon);
          expect(
            d.f.network.requests.where(
              (request) => request.url.path.startsWith('/subtitles/'),
            ),
            hasLength(requests),
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
