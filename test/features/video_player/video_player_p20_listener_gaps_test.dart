import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

Future<void> _background(PipLifecycleDriver d) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    await d.lifecycle(state);
  }
}

void main() {
  // Before any tracker singleton binds a client in this isolate.
  TraktTestTransport.install();
  testWidgets(
    'P20 a play edge while backgrounded is paused again and never scrobbles a start',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final cipher = (await t.runAsync(() => seedTrakt()))!;
      f.network.handler = traktReply;
      try {
        await d.mount(traktScreen(type: 'movie', season: null, episode: null));
        await d.settle();
        await _background(d);
        await d.settle();
        final pauses = d.operations('pause').length;
        final scrobbles = f.network.requests
            .where((r) => r.url.path == '/scrobble/start')
            .length;
        f.player.state = f.player.state.copyWith(playing: true);
        f.player.emit('playing', true);
        await d.settle();
        expect(d.operations('pause').length, pauses + 1);
        expect(
          f.network.requests
              .where((r) => r.url.path == '/scrobble/start')
              .length,
          scrobbles,
        );
      } finally {
        cipher.releaseAll();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a live channel narrates its first frame, rebuffer, error and end through the tune diagnostics',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final live = IptvChannel(
        name: 'P20 narrated',
        url: 'https://listener.test/live.ts',
        contentType: 'live',
        group: 'News',
      );
      List<String> events() => [
        for (final l in d.logs)
          if (l.startsWith('IptvDiag: ')) l.split(' ')[2],
      ];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: live.url,
            title: live.name,
            iptvChannels: [live],
            iptvStartIndex: 0,
          ),
        );
        expect(events().take(2), ['event=tune-start', 'event=first-frame']);
        final p = d.player;
        p.emit('buffering', true);
        await d.f.advance(t);
        p.emit('buffering', false);
        await d.f.advance(t);
        p.emit('error', 'HTTP error 404 Not Found');
        await d.f.advance(t);
        p.emit('completed', true);
        await d.f.advance(t);
        expect(
          events().skip(2).where((e) => e != 'event=recovery').take(4).toList(),
          [
            'event=rebuffer-start',
            'event=rebuffer-end',
            'event=error',
            'event=ended',
          ],
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 only subtitle, libass and track mpv logs reach the subtitle diagnostics',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      List<String> diag() => [
        for (final l in d.logs)
          if (l.startsWith('[SubtitleDiag] mpv[')) l,
      ];
      try {
        await d.mount();
        final before = diag().length;
        for (final (prefix, text) in [
          ('cplayer', 'starting playback'),
          ('sub', 'loaded external file'),
          ('ffmpeg', 'LIBASS font cache ready'),
          ('demux', 'selected TRACK 2'),
          ('vo', 'frame dropped'),
        ]) {
          d.player.emit(
            'log',
            mk.PlayerLog(prefix: prefix, level: 'v', text: text),
          );
        }
        await d.f.advance(t);
        expect(diag().skip(before), [
          '[SubtitleDiag] mpv[v] sub: loaded external file',
          '[SubtitleDiag] mpv[v] ffmpeg: LIBASS font cache ready',
          '[SubtitleDiag] mpv[v] demux: selected TRACK 2',
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a renderer rebuild never reports the torn-down player pausing to Trakt',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      final cipher = (await t.runAsync(() => seedTrakt()))!;
      d.f.network.handler = traktReply;
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      List<String> actions() => [
        for (final r in d.f.network.requests)
          if (r.url.host == 'api.trakt.tv' &&
              r.url.path.startsWith('/scrobble/'))
            r.url.path.split('/').last,
      ];
      try {
        await d.f.finish<void>(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        await d.mount(
          screen: traktScreen(type: 'movie', season: null, episode: null),
        );
        await d.f.actions.settle(t);
        expect(actions(), ['start']);
        d.player.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        if (!d.player.readyDelivered) d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.actions.settle(t);
        expect(actions().where((a) => a == 'pause'), isEmpty);
      } finally {
        VpS2Hooks.install(null);
        cipher.releaseAll();
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );

  testWidgets(
    'P20 only video params with a positive width count as the first IPTV frame',
    (t) async {
      final d = EngineDriver(
        t,
        configurePlayer: (p) => p.onOpen = () {
          // Readiness without a sized frame: the test publishes params itself.
          p.state = p.state.copyWith(duration: const Duration(minutes: 20));
          p.emit('duration', const Duration(minutes: 20));
        },
      );
      await d.initialize();
      final live = IptvChannel(
        name: 'P20 sized frame',
        url: 'https://listener.test/sized.ts',
        contentType: 'live',
        group: 'News',
      );
      int frames() =>
          d.logs.where((l) => l.contains(' event=first-frame ')).length;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: live.url,
            title: live.name,
            iptvChannels: [live],
            iptvStartIndex: 0,
          ),
        );
        expect(frames(), 0);
        for (final params in [
          const mk.VideoParams(),
          const mk.VideoParams(w: 0, h: 0),
        ]) {
          d.player.emit('videoParams', params);
          await d.f.advance(t);
          expect(frames(), 0, reason: 'w=${params.w}');
        }
        d.player.emit('videoParams', const mk.VideoParams(w: 1, h: 1));
        await d.f.advance(t);
        expect(frames(), 1);
      } finally {
        await d.close();
      }
    },
  );

  for (final renderer in [false, true]) {
    testWidgets(
      'P20 on an explicit Android renderer ${renderer ? 'a renderer failure falls back with reason renderer_error' : 'an ordinary stream error never rebuilds the player'}',
      (t) async {
        final d = EngineDriver(t);
        await d.initialize();
        VpS2Hooks.install(VpS2Hooks(android: () => true));
        try {
          await d.f.finish<void>(
            t,
            PlayerSettingsStorage.setAndroidVideoRendererMode(
              AndroidVideoRendererMode.directSurface,
            ),
          );
          await d.mount();
          d.player.emit(
            'error',
            renderer
                ? 'synthetic MediaCodec video output failure'
                : 'HTTP error 404 Not Found',
          );
          await d.f.advance(t, const Duration(seconds: 2));
          if (renderer && !d.player.readyDelivered) d.player.deliverReady();
          await d.f.advance(t, const Duration(seconds: 1));
          expect(d.f.players, hasLength(renderer ? 2 : 1));
          expect([
            for (final l in d.decoderLines)
              if (l.contains(' phase=fallback ')) l.split(' ').last,
          ], renderer ? ['reason=renderer_error'] : isEmpty);
        } finally {
          VpS2Hooks.install(null);
          await d.close();
        }
      },
    );
  }

  for (final ios in [true, false]) {
    testWidgets(
      'P20 position ticks ${ios ? 'push the PiP playback state once per new second on iOS' : 'never push PiP playback state on Android'}',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        final d = PipLifecycleDriver(t, f, ios: ios);
        await d.initialize();
        try {
          await d.mount();
          final before = d.named('updatePlaybackState').length;
          for (final ms in [61000, 61500, 62000, 62400]) {
            f.player.emit('position', Duration(milliseconds: ms));
            await f.advance(t);
          }
          expect(d.named('updatePlaybackState').length - before, ios ? 2 : 0);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets('P20 a position tick reaches the on-screen playback clock', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount();
      d.player.state = d.player.state.copyWith(
        position: const Duration(minutes: 3, seconds: 5),
      );
      d.player.emit('position', const Duration(minutes: 3, seconds: 5));
      await d.f.advance(t, const Duration(milliseconds: 300));
      expect(find.textContaining('03:05'), findsWidgets);
    } finally {
      await d.close();
    }
  });

  for (final policy in [true, false]) {
    testWidgets(
      'P20 ${policy ? 'with' : 'without'} a subtitle policy an audio track change ${policy ? 'refreshes' : 'never refreshes'} the audio-language policy',
      (t) async {
        final d = EngineDriver(t);
        await d.initialize();
        int reads() => d
            .propertyReads()
            .where((p) => p == 'current-tracks/audio/lang')
            .length;
        void select(String id, String language, {String subtitle = '1'}) =>
            d.player.publishTracks(
              d.player.state.tracks,
              selected: mk.Track(
                audio: mk.AudioTrack(id, 'Audio $id', language),
                subtitle: d.player.state.tracks.subtitle.firstWhere(
                  (s) => s.id == subtitle,
                  orElse: () => mk.SubtitleTrack.no(),
                ),
              ),
            );
        try {
          await d.f.finish<void>(
            t,
            SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(policy),
          );
          await d.mount();
          await d.f.actions.settle(t);
          final before = reads();
          select('2', 'spa');
          await d.f.actions.settle(t);
          final afterAudio = reads();
          select('2', 'spa', subtitle: '2');
          await d.f.actions.settle(t);
          final afterSubtitle = reads();
          select('2', 'fra');
          await d.f.actions.settle(t);
          expect([
            afterAudio - before,
            afterSubtitle - afterAudio,
            reads() - afterSubtitle,
          ], policy ? [1, 0, 1] : [0, 0, 0]);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets('P20 a duration change reaches the on-screen playback clock', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount();
      d.player.state = d.player.state.copyWith(
        duration: const Duration(minutes: 42, seconds: 10),
      );
      d.player.emit('duration', const Duration(minutes: 42, seconds: 10));
      await d.f.advance(t, const Duration(milliseconds: 300));
      expect(find.textContaining('42:10'), findsWidgets);
    } finally {
      await d.close();
    }
  });

  testWidgets('P20 a pause edge alone repaints the play state', (t) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount();
      expect(t.widget<Controls>(find.byType(Controls)).isPlaying, isTrue);
      d.player.emit('playing', false);
      await d.f.advance(t);
      expect(t.widget<Controls>(find.byType(Controls)).isPlaying, isFalse);
    } finally {
      await d.close();
    }
  });

  double spinner(WidgetTester t) => t
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byType(BufferingIndicator),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  testWidgets('P20 a repeated buffering edge restarts the spinner debounce', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount();
      final p = d.player;
      p.state = p.state.copyWith(buffering: true);
      p.emit('buffering', true);
      await d.f.advance(t, const Duration(milliseconds: 500));
      p.emit('buffering', true);
      await d.f.advance(t, const Duration(milliseconds: 500));
      expect(spinner(t), 0);
      await d.f.advance(t, const Duration(milliseconds: 400));
      expect(spinner(t), 1);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P20 a buffering-false edge cancels the pending spinner even if mpv flips back unannounced',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final p = d.player;
        p.state = p.state.copyWith(buffering: true);
        p.emit('buffering', true);
        await d.f.advance(t, const Duration(milliseconds: 300));
        p.emit('buffering', false);
        // The native state reads buffering again without a stream event.
        await d.f.advance(t, const Duration(milliseconds: 1000));
        expect(spinner(t), 0);
      } finally {
        await d.close();
      }
    },
  );
}
