import 'dart:async';

import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'identify manual episode wins over incoming Stremio coordinates while guide pause is pending',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [
        IdentifyTitleDriver.identityMeta('Chosen series', type: 'series'),
      ];
      final pause = Completer<void>();
      Future<void>? switching;
      try {
        await d.mountIdentity(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/review-manual.mp4',
            title: 'Unparsed launch',
            stremioTvChannels: const [
              {'id': 'a', 'name': 'A'},
              {'id': 'b', 'name': 'B'},
            ],
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: (_) async => null,
          ),
        );
        final menu = await d.menu();
        final initial = d.start(menu);
        await d.found('Chosen series');
        await t.tap(find.text('Chosen series'));
        await d.episode('2', '3');
        final committed = await d.f.finish(t, initial);
        expect(committed?.season, 2);
        expect(committed?.episode, 3);
        d.panel.onClose();
        await d.f.advance(t);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        final guide = t.widget<StremioTvGuideSheet>(
          find.byType(StremioTvGuideSheet),
        );
        d.player.delays['pause'] = pause;
        final pauses = d.player.calls.where((v) => v.$1 == 'pause').length;
        switching = d.observe(
          () => (guide.onChannelSwitched as dynamic)(
            'b',
            'https://player.test/review-incoming.mp4',
            'Incoming unparsed title',
            contentImdbId: 'tt1200009',
            contentType: 'series',
            contentSeason: 7,
            contentEpisode: 9,
          ),
        );
        await d.f.until(
          t,
          () => d.player.calls.where((v) => v.$1 == 'pause').length > pauses,
        );
        expect(pause.isCompleted, isFalse);
        // Invoke the real menu action while the guide's native pause is held.
        // Incoming metadata is already written; the subtitle reset is later.
        final pending = d.start(menu);
        await d.found('Chosen series');
        expect(d.searchField.controller.text, 'Incoming unparsed title');
        await t.tap(find.text('Chosen series'));
        final result = await d.f.finish(t, pending);
        expect(pause.isCompleted, isFalse);
        expect(find.text('Which episode?'), findsNothing);
        expect(result?.season, 2);
        expect(result?.episode, 3);
        expect(result?.identityLabel, 'Subtitles for Chosen series S2E3');
        expect(d.subtitlePaths.last, '/subtitles/series/tt1200002:2:3.json');
        pause.complete();
        d.player.delays.remove('pause');
        await d.f.finish(t, switching!);
        expect(d.errors, isEmpty);
      } finally {
        if (!pause.isCompleted) pause.complete();
        if (d.f.players.isNotEmpty) d.player.delays.remove('pause');
        if (switching != null) await d.f.finish(t, switching);
        await removeFixture(d);
      }
    },
  );
  testWidgets('identify season without episode opens empty coordinate dialog', (
    t,
  ) async {
    final d = IdentifyTitleDriver(t);
    await d.setupIdentity();
    d.metas = [
      IdentifyTitleDriver.identityMeta('Partial series', type: 'series'),
    ];
    try {
      await d.mountIdentity(
        screen: const VideoPlayerScreen(
          videoUrl: 'https://player.test/review-partial.mp4',
          title: 'Unparsed title',
          contentSeason: 7,
        ),
      );
      final pending = d.start(await d.menu());
      await d.found('Partial series');
      await t.tap(find.text('Partial series'));
      await d.found('Which episode?');
      expect(
        t
            .widgetList<TextField>(find.byType(TextField))
            .where(
              (w) => ['Season', 'Episode'].contains(w.decoration?.labelText),
            )
            .map((w) => w.controller!.text),
        ['', ''],
      );
      expect(d.subtitlePaths, isEmpty);
      await d.episode('4', '6');
      final result = await d.f.finish(t, pending);
      expect(result?.season, 4);
      expect(result?.episode, 6);
      expect(d.subtitlePaths, ['/subtitles/series/tt1200002:4:6.json']);
      expect(d.errors, isEmpty);
    } finally {
      await removeFixture(d);
    }
  });
  testWidgets(
    'identify catalog effective non-IMDb id is never selectable or committed',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [
        {
          ...IdentifyTitleDriver.identityMeta('Invalid IMDb'),
          'imdb_id': const CustomSeriesIdentity('fixture', 'native-series').id,
        },
      ];
      try {
        await d.mountIdentity();
        final menu = await d.menu();
        final pending = d.start(menu);
        await d.found('No IMDb-backed results found');
        expect(find.text('Invalid IMDb'), findsNothing);
        expect(d.catalogQueries, ['Launch Title']);
        expect(d.subtitlePaths, isEmpty);
        expect(menu.subtitleIdentityLabel, 'Detected: Launch Title');
        await d.dismiss();
        expect(await d.f.finish(t, pending), isNull);
        expect(d.panel.subtitleIdentityLabel, 'Detected: Launch Title');
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
