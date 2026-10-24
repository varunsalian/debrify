import 'package:debrify/features/video_player/application/vp_filename_hash.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/lease_steps.dart';
import 'support/startup_driver.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';

final _wakeDrain = Object();

String _opened(EngineDriver d) {
  final open = d.player.calls.firstWhere((c) => c.$1 == 'open');
  return ((open.$2 as (mk.Playable, bool)).$1 as mk.Media).uri;
}

Future<String> _start(
  WidgetTester t,
  VideoPlayerScreen screen, {
  Future<void> Function(EngineDriver)? seed,
}) async {
  final d = EngineDriver(t);
  await d.initialize();
  try {
    if (seed != null) await seed(d);
    await d.mount(screen: screen);
    expect(d.errors, isEmpty);
    return _opened(d);
  } finally {
    await d.close();
  }
}

const _movies = [
  PlaylistEntry(url: 'https://gaps.test/m0.mkv', title: 'Gap one.mkv'),
  PlaylistEntry(url: 'https://gaps.test/m1.mkv', title: 'Gap two.mkv'),
];

/// Stores a resume row for every movie, then rewrites each row's updatedAt
/// (null removes the field, as on rows written before it existed).
Future<void> _rows(EngineDriver d, List<int?> updatedAt) async {
  for (final entry in _movies) {
    await d.f.finish<void>(
      d.t,
      VideoProgressStorage.saveVideoPlaybackState(
        videoTitle: vpFilenameHash(entry.title),
        videoUrl: entry.url,
        positionMs: 60000,
        durationMs: 1200000,
      ),
    );
  }
  final map = await d.f.finish(d.t, PlaybackStateStore.getPlaybackStateMap());
  for (final raw in map.values) {
    final row = raw as Map;
    final index = _movies.indexWhere(
      (e) => vpFilenameHash(e.title) == row['title'],
    );
    if (index < 0) continue;
    final value = updatedAt[index];
    if (value == null) {
      row.remove('updatedAt');
    } else {
      row['updatedAt'] = value;
    }
  }
  await d.f.finish(d.t, PlaybackStateStore.savePlaybackStateMap(map));
}

void main() {
  // Before any tracker singleton binds a client in this isolate.
  TraktTestTransport.install();
  testWidgets(
    'P20 collection rows without updatedAt keep the first stored entry',
    (t) async {
      final url = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://gaps.test/m0.mkv',
          title: 'P20 gap rows',
          contentType: 'movie',
          playlist: _movies,
        ),
        seed: (d) => _rows(d, [null, null]),
      );
      expect(url, _movies[0].url);
    },
  );

  testWidgets('P20 a dated collection row wins over an earlier undated one', (
    t,
  ) async {
    final url = await _start(
      t,
      const VideoPlayerScreen(
        videoUrl: 'https://gaps.test/m0.mkv',
        title: 'P20 gap rows',
        contentType: 'movie',
        playlist: _movies,
      ),
      seed: (d) => _rows(d, [null, 1]),
    );
    expect(url, _movies[1].url);
  });

  testWidgets(
    'P20 a Stremio TV guide launch presents the launch title as the clean dynamic title on TV',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://gaps.test/slot.mp4',
            title: 'P20 Stremio launch title',
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P20 slot'},
              {'id': 'other', 'name': 'P20 other'},
            ],
            stremioTvCurrentChannelId: 'slot',
            stremioTvChannelSwitchProvider: (_) async => null,
          ),
        );
        final controls = t.widget<TvControls>(find.byType(TvControls));
        expect(controls.title, 'P20 Stremio launch title');
        expect(controls.titleIsClean, isTrue);
      } finally {
        PlatformUtil.debugSetAndroidTvCached(false);
        await d.close();
      }
    },
  );

  testWidgets('P20 startup offers the new player to subtitle auto-sync once', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: const VideoPlayerScreen(
          videoUrl: 'https://gaps.test/sync.mp4',
          title: 'P20 sync install',
        ),
      );
      expect(
        d.logs.where((l) => l.startsWith('SubtitleAutoSync: not installing')),
        hasLength(1),
      );
    } finally {
      await d.close();
    }
  });

  final vod = IptvChannel(
    name: 'P20 diag vod',
    url: 'https://gaps.test/vod.mp4',
    contentType: 'vod',
  );
  final live = IptvChannel(
    name: 'P20 diag live',
    url: 'https://gaps.test/live.ts',
    contentType: 'live',
  );

  for (final (start, expected) in [
    (null, 'live=false ch="P20 diag vod"'),
    (0, 'live=false ch="P20 diag vod"'),
    (5, 'live=true ch="?"'),
  ]) {
    testWidgets(
      'P20 an IPTV launch at start index $start records its first tune for the launch channel',
      (t) async {
        final lavf = <String>[];
        final d = EngineDriver(
          t,
          configurePlayer: (p) {
            (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
              if (name != 'setProperty') return;
              final (key, v) = value as (String, String);
              if (key == 'stream-lavf-o') lavf.add(v);
            };
          },
        );
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: vod.url,
              title: vod.name,
              iptvChannels: [vod, live],
              iptvStartIndex: start,
            ),
          );
          expect(d.logs.where((l) => l.contains('event=tune-start')), [
            'IptvDiag: gen=1 event=tune-start proto=progressive $expected '
                'url=https://gaps.test/…/vod.mp4',
          ]);
          expect(lavf.first == '', start != 5);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 a failed lazy series launch enters the ranked ladder at source two',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      await d.rules(series: true);
      final a = startupSource('series-lazy-first');
      final b = startupSource('series-lazy-next');
      try {
        await d.begin(
          d.screen(
            type: 'series',
            sources: [a, b],
            url: '',
            failover: true,
            entries: const [
              PlaylistEntry(url: '', title: 'lazy', provider: 'torbox'),
            ],
          ),
        );
        await d.committed();
        expect(d.opens, [b.directUrl]);
      } finally {
        await d.close();
        await t.runAsync(
          () => PlayerDisplayControls.instance.setWakelockOwner(
            _wakeDrain,
            false,
          ),
        );
      }
    },
  );

  testWidgets(
    'P20 an external-audio launch opened paused is still meant to play: a renderer rebuild resumes it playing',
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
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://gaps.test/video.mp4',
            title: 'P20 audio rebuild',
            audioUrl: 'https://gaps.test/audio.m4a',
          ),
        );
        d.player.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        if (!d.player.readyDelivered) d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        final reopened = [
          for (final c in d.player.calls)
            if (c.$1 == 'open') (c.$2 as (mk.Playable, bool)).$2,
        ];
        // Reopened paused for the audio attach, then played: the launch's
        // desired play state survives the paused open.
        expect(reopened, [false]);
        expect(
          [
            for (final c in d.player.calls)
              if (c.$1 == 'open' || c.$1 == 'audio' || c.$1 == 'play') c.$1,
          ],
          ['open', 'audio', 'play'],
        );
      } finally {
        VpS2Hooks.install(null);
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a failed external-audio open is not reported as a startup failure',
    (t) async {
      final d = EngineDriver(
        t,
        configurePlayer: (p) => p.failures['open'] = StateError('open failed'),
      );
      await d.initialize();
      try {
        await pumpScreen(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://gaps.test/audio-fail.mp4',
            title: 'P20 audio fail',
            audioUrl: 'https://gaps.test/audio-fail.m4a',
          ),
        );
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        await d.f.advance(t, const Duration(milliseconds: 300));
        expect(find.text('No playable source could be started.'), findsNothing);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 the controls auto-hide after a completed start', (t) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: const VideoPlayerScreen(
          videoUrl: 'https://gaps.test/hide.mp4',
          title: 'P20 auto hide',
        ),
      );
      await d.f.advance(t, const Duration(seconds: 6));
      expect(
        t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(Controls),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity,
        0,
      );
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P20 a late startup throw after a good open still re-arms tracking so Trakt hears the start',
    (t) async {
      final d = EngineDriver(
        t,
        configurePlayer: (p) => p.failures['seek'] = StateError('seek failed'),
      );
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      final cipher = (await t.runAsync(() => seedTrakt()))!;
      d.f.network.handler = traktReply;
      try {
        await d.f.finish<void>(
          t,
          VideoProgressStorage.saveVideoPlaybackState(
            videoTitle: 'Trakt fixture',
            videoUrl: 'https://player.test/trakt.mp4',
            positionMs: 240000,
            durationMs: 1200000,
          ),
        );
        await d.mount(
          screen: traktScreen(type: 'movie', season: null, episode: null),
        );
        await d.f.actions.settle(t);
        expect(
          d.logs.where(
            (l) => l.startsWith('VideoPlayer: initial open failed:'),
          ),
          hasLength(1),
        );
        expect(
          [
            for (final r in d.f.network.requests)
              if (r.url.host == 'api.trakt.tv' &&
                  r.url.path.startsWith('/scrobble/'))
                r.url.path.split('/').last,
          ],
          ['start'],
        );
      } finally {
        cipher.releaseAll();
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );

  testWidgets(
    'P20 a typed launch with ranked sources but no URL and no failed attempt opens nothing',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      await d.rules();
      final a = startupSource('no-url-ranked');
      try {
        await d.begin(d.screen(sources: [a], url: '', failover: true));
        await d.f.until(
          t,
          () => d.periodic.any((p) => p.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
        expect(d.opens, isEmpty);
      } finally {
        await d.close();
        await t.runAsync(
          () => PlayerDisplayControls.instance.setWakelockOwner(
            _wakeDrain,
            false,
          ),
        );
      }
    },
  );
}
