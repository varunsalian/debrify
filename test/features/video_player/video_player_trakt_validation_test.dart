import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Trakt startup validation release sends start and arms heartbeat after auth completed inside the gate',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (player) {
          player.onOpen = () {};
        },
      );
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        d.cipher.hold = true;
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: traktScreen(),
          ),
        );
        await f.until(t, () => f.controllers.isNotEmpty);
        f.player.deliverReady();
        await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
        f.player.emit('duration', const Duration(minutes: 20));
        f.player.emit('playing', true);
        await d.drain();
        d.cipher.releaseAll();
        await d.drain();
        expect(d.requests, isEmpty);
        f.player.publishFrame();
        f.controllers.last.publishFrame();
        await f.until(t, () => d.actions.isNotEmpty);
        expect(d.actions, ['start']);
        d.expectRequest(0, 'start', 80 / 1200000 * 100);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.actions, ['start', 'start']);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'Trakt manual validation suppresses seek heartbeat and disposal scrobble despite live stream events',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final opened = Completer<void>();
      final a = source('Original', 'https://player.test/trakt-a.mp4');
      final b = source('Pending', 'https://player.test/trakt-b.mp4');
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Trakt fixture',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            traktScrobble: true,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        expect(d.actions, ['start']);
        f.player.delays['open'] = opened;
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        sheet.onSourceSelected(1, b.directUrl!);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        f.player.state = f.player.state.copyWith(
          playing: true,
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', const Duration(minutes: 20));
        f.player.emit('playing', true);
        await d.drain();
        await f.key(t, LogicalKeyboardKey.mediaFastForward);
        await d.drain();
        expect(d.actions, ['start']);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.actions, ['start']);
        await t.pumpWidget(const SizedBox.shrink());
        await d.drain();
        expect(d.actions, ['start']);
        opened.complete();
        await d.drain();
        expect(d.actions, ['start']);
      } finally {
        if (!opened.isCompleted) opened.complete();
        await d.close();
      }
    },
  );
}
