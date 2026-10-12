import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Trakt seek target before landing is sent immediately without sampling the old position',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final landing = Completer<void>();
      try {
        await d.mount(traktScreen());
        f.player.delays['seek'] = landing;
        final controls = playerControls(t);
        controls.onSeekBarChanged(.25);
        controls.onSeekBarChangeEnd();
        await d.drain();
        expect(d.actions, ['start', 'start']);
        d.expectRequest(1, 'start', 25);
        expect(f.player.state.position, const Duration(milliseconds: 80));
        landing.complete();
        await d.drain();
        expect(f.player.state.position, const Duration(seconds: 300));
      } finally {
        if (!landing.isCompleted) landing.complete();
        await d.close();
      }
    },
  );
  testWidgets(
    'Trakt disabled user key cancels deferred Stremio startup offset before duration arrives',
    (t) async {
      late VideoPlayerEnvironment f;
      f = VideoPlayerEnvironment(
        configurePlayer: (player) {
          player.onOpen = () {
            player.publishFrame(duration: Duration.zero);
            f.controllers.last.publishFrame();
          };
        },
      );
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            home: const VideoPlayerScreen(
              videoUrl: 'https://player.test/deferred.mp4',
              title: 'Deferred Trakt',
              startAtPercent: .5,
              stremioTvChannels: [
                {'id': 'a', 'name': 'A'},
              ],
              stremioTvCurrentChannelId: 'a',
            ),
          ),
        );
        await f.until(t, () => f.controllers.isNotEmpty);
        f.player.deliverReady();
        await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
        await d.drain();
        expect(d.seeks, isEmpty);
        await f.key(t, LogicalKeyboardKey.mediaFastForward);
        expect(d.seeks, [Duration.zero]);
        f.player.state = f.player.state.copyWith(
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', const Duration(minutes: 20));
        await d.drain();
        expect(
          d.seeks,
          [Duration.zero],
          reason:
              'A duration tick cannot revive the user-cancelled startup seek',
        );
        expect(d.requests, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final active in [false, true]) {
    testWidgets(
      'Trakt ${active ? 'validation-active' : 'disabled'} key releases held resume target before its early return',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final seek = Completer<void>();
        try {
          t.view.physicalSize = const Size(1280, 800);
          t.view.devicePixelRatio = 1;
          d.cipher.hold = true;
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              home: traktScreen(enabled: active, percent: 50),
            ),
          );
          await f.until(t, () => f.controllers.isNotEmpty);
          if (active) {
            f.player.delays['seek'] = seek;
          } else {
            f.player.failures['seek'] = StateError('synthetic unlanded resume');
          }
          f.player.deliverReady();
          await f.until(t, () => d.seeks.isNotEmpty);
          expect(d.seeks.first, const Duration(seconds: 600));
          await d.drain();
          d.cipher.releaseAll();
          await d.drain();
          expect(
            d.requests,
            isEmpty,
            reason: 'No start escapes the held initial validator',
          );
          await f.key(t, LogicalKeyboardKey.mediaFastForward);
          expect(d.seeks.last, const Duration(milliseconds: 10080));
          seek.complete();
          await d.drain();
          if (active) await f.until(t, () => d.requests.isNotEmpty);
          playerControls(t).onPlayPause();
          await d.drain();
          final record = await t.runAsync(
            () => SeriesProgressStorage.getSeriesPlaybackState(
              seriesTitle: 'Trakt fixture',
              imdbId: 'tt5100000',
              season: 2,
              episode: 3,
            ),
          );
          expect(record?['positionMs'], 10080);
          expect(
            d.seeks.where((p) => p == const Duration(seconds: 600)),
            hasLength(1),
          );
          if (active) {
            d.expectRequest(0, 'start', 10080 / 1200000 * 100);
          } else {
            expect(d.requests, isEmpty);
          }
        } finally {
          if (!seek.isCompleted) seek.complete();
          await d.close();
        }
      },
    );
  }
}
