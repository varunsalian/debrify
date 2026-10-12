import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Trakt progress samples held unlanded resume rather than the raw restart position',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) {
          p.failures['seek'] = StateError('synthetic unlanded resume');
        },
      );
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen(percent: 50));
        expect(f.player.state.position, const Duration(milliseconds: 80));
        expect(d.actions, ['start']);
        d.expectRequest(0, 'start', 50);
        await d.playing(false);
        d.expectRequest(1, 'pause', 50);
      } finally {
        await d.close();
      }
    },
  );
  for (final gate in ['paused', 'duration', 'coordinates', 'identity']) {
    testWidgets(
      'Trakt heartbeat live gates $gate retain the original timer without sending or logging a checkpoint',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final oldPrint = debugPrint;
        final logs = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          await d.mount(traktScreen());
          await d.position(972000);
          await d.playing(true);
          expect(d.actions, ['start', 'stop']);
          await d.position(300000);
          if (gate == 'paused') await d.playing(false);
          if (gate == 'duration') {
            f.player.emit('duration', Duration.zero);
            await f.advance(t);
          }
          if (gate == 'coordinates' || gate == 'identity') {
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: f.navigator,
                theme: ThemeData.dark(),
                home: traktScreen(
                  id: gate == 'identity' ? null : 'tt5100000',
                  season: gate == 'coordinates' ? null : 2,
                  episode: gate == 'coordinates' ? null : 3,
                ),
              ),
            );
          }
          await f.advance(t, const Duration(minutes: 2));
          await d.drain();
          expect(d.actions, ['start', 'stop']);
          expect(logs.where((s) => s.startsWith('Trakt: Heartbeat')), isEmpty);
          expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
        } finally {
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }
  for (final sample in ['zero', 'negative', 'beyond', 'subsecond']) {
    testWidgets(
      'Trakt progress $sample duration or position uses original clamped percent',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen());
          if (sample == 'zero') {
            f.player.emit('duration', Duration.zero);
            await f.advance(t);
          }
          if (sample == 'subsecond') {
            f.player.emit('duration', const Duration(milliseconds: 500));
            await f.advance(t);
          }
          await d.position(
            sample == 'subsecond'
                ? 125
                : sample == 'negative'
                ? -60000
                : sample == 'beyond'
                ? 1500000
                : 600000,
          );
          await d.playing(false);
          expect(d.actions, ['start', sample == 'beyond' ? 'stop' : 'pause']);
          d.expectRequest(
            1,
            sample == 'beyond' ? 'stop' : 'pause',
            sample == 'beyond'
                ? 100
                : sample == 'subsecond'
                ? 25
                : 0,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Trakt live widget identity and media type drive pause and heartbeat without reinitializing State',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen());
        await d.position(300000);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: traktScreen(id: 'tt5200000', type: 'movie', enabled: false),
          ),
        );
        await d.playing(false);
        d.expectRequest(1, 'pause', 25, id: 'tt5200000', movie: true);
        await d.playing(true);
        d.expectRequest(2, 'start', 25, id: 'tt5200000', movie: true);
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        d.expectRequest(3, 'start', 25, id: 'tt5200000', movie: true);
        expect(f.players, hasLength(1));
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: traktScreen(id: null),
          ),
        );
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        await d.seek(.5);
        expect(d.requests, hasLength(4));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Trakt unresolved episode creates no latent seek or start heartbeat when coordinates arrive later',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(traktScreen(season: null, episode: null));
        await d.playing(true);
        await d.seek(.25);
        expect(d.requests, isEmpty);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: traktScreen(),
          ),
        );
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(d.requests, isEmpty);
        await d.playing(true);
        expect(d.actions, ['start']);
        d.expectRequest(0, 'start', 25);
      } finally {
        await d.close();
      }
    },
  );

  for (final heartbeat in [false, true]) {
    testWidgets(
      'Trakt shared percent through Simkl ${heartbeat ? 'heartbeat' : 'pause'} retains current progress',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await t.runAsync(() async {
            await SimklStorage.setSimklAccessToken('vplayer-synthetic-simkl');
            await TrackingSourceStorage.setTrackingScrobbleTargets({
              TrackingSource.simkl,
            });
          });
          await f.mount(
            t,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/simkl.mp4',
              title: 'Shared percent',
              contentImdbId: 'tt5100000',
              contentType: 'series',
              contentSeason: 2,
              contentEpisode: 3,
              simklScrobble: true,
            ),
          );
          await d.position(300000);
          await d.playing(true);
          if (heartbeat) {
            await f.advance(t, const Duration(minutes: 2));
          } else {
            await d.playing(false);
          }
          await d.drain();
          final calls = f.network.requests
              .where(
                (r) =>
                    r.url.host == 'api.simkl.com' &&
                    r.url.path == '/scrobble/pause',
              )
              .toList();
          expect(calls, hasLength(1));
          expect((jsonDecode(calls.single.body) as Map)['progress'], 25);
          expect(d.requests, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
