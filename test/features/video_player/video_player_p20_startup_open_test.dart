import 'dart:convert';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/lease_steps.dart';
import 'support/player_actions.dart';
import 'support/startup_driver.dart';

final _wakeDrain = Object();
const _url = 'https://startup-open.test/movie.mp4';

List<(mk.Media, bool)> _opens(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'open')
      (
        (c.$2 as (mk.Playable, bool)).$1 as mk.Media,
        (c.$2 as (mk.Playable, bool)).$2,
      ),
];

List<Object?> _seeks(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'seek') c.$2,
];

Future<void> _resume(EngineDriver d, String title, Duration at) =>
    d.f.finish<void>(
      d.t,
      VideoProgressStorage.saveVideoPlaybackState(
        videoTitle: title,
        videoUrl: _url,
        positionMs: at.inMilliseconds,
        durationMs: const Duration(minutes: 20).inMilliseconds,
      ),
    );

const _lazy = PlaylistEntry(
  url: '',
  title: 'Lazy.Launch.mkv',
  provider: 'torbox',
  torboxTorrentId: 41,
  torboxFileId: 7,
);

Future<EngineDriver> _lazyStart(
  WidgetTester t, {
  required String videoUrl,
  required List<http.Response> replies,
  bool settle = true,
}) async {
  final d = EngineDriver(t);
  await d.initialize();
  await d.f.finish<void>(t, TorboxStorage.saveTorboxApiKey('tb-key'));
  var served = 0;
  d.f.network.handler = (r) {
    if (r.url.path.endsWith('/torrents/requestdl')) {
      final reply = replies[served.clamp(0, replies.length - 1)];
      served++;
      return reply;
    }
    return http.Response('{}', 404);
  };
  await d.mount(
    screen: VideoPlayerScreen(
      videoUrl: videoUrl,
      title: 'P20 lazy launch',
      playlist: const [_lazy],
      disableAutoResume: true,
    ),
    settleInitialization: settle,
  );
  return d;
}

http.Response _link(String url) =>
    http.Response(jsonEncode({'success': true, 'data': url}), 200);

void main() {
  testWidgets(
    'P20 a lazy launch entry is resolved and its link opened and played',
    (t) async {
      final d = await _lazyStart(
        t,
        videoUrl: '',
        replies: [_link('https://cdn.test/lazy.mkv')],
      );
      try {
        final opens = _opens(d.player);
        expect(opens.map((o) => o.$1.uri), ['https://cdn.test/lazy.mkv']);
        expect(opens.map((o) => o.$2), [true]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a failed lazy resolve with no URL and no ranked sources reloads the entry paused',
    (t) async {
      final d = await _lazyStart(
        t,
        videoUrl: '',
        replies: [
          http.Response('{}', 500),
          _link('https://cdn.test/second.mkv'),
        ],
      );
      try {
        final opens = _opens(d.player);
        expect(opens.map((o) => o.$1.uri), ['https://cdn.test/second.mkv']);
        expect(opens.map((o) => o.$2), [false]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 external audio opens paused, attaches the track after readiness and only then plays',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: _url,
            title: 'P20 external audio',
            audioUrl: 'https://startup-open.test/audio.m4a',
          ),
        );
        final names = [
          for (final c in d.player.calls)
            if (c.$1 == 'open' || c.$1 == 'audio' || c.$1 == 'play') c.$1,
        ];
        expect(names, ['open', 'audio', 'play']);
        expect(_opens(d.player).map((o) => o.$2), [false]);
        final audio = d.player.calls.firstWhere((c) => c.$1 == 'audio').$2;
        expect((audio as mk.AudioTrack).uri, isTrue);
        expect(audio.id, 'https://startup-open.test/audio.m4a');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a percent start seeks to that share of the duration instead of the stored resume',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await _resume(d, 'P20 percent', const Duration(minutes: 3));
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: _url,
            title: 'P20 percent',
            startAtPercent: .5,
          ),
        );
        expect(_seeks(d.player), [const Duration(minutes: 10)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a random start seeks once inside the allowed share and ignores the stored resume',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await _resume(d, 'P20 random', const Duration(minutes: 3));
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: _url,
            title: 'P20 random',
            startFromRandom: true,
            randomStartMaxPercent: 10,
          ),
        );
        final seeks = _seeks(d.player);
        expect(seeks, hasLength(1));
        expect(
          (seeks.first! as Duration) <= const Duration(minutes: 2),
          isTrue,
          reason: 'at most 10% of 20 minutes',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a random start with no usable share falls back to the stored resume',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await _resume(d, 'P20 random none', const Duration(minutes: 3));
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: _url,
            title: 'P20 random none',
            startFromRandom: true,
            randomStartMaxPercent: 0,
          ),
        );
        expect(_seeks(d.player), [const Duration(minutes: 3)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 a plain launch restores the stored resume position', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await _resume(d, 'P20 plain resume', const Duration(minutes: 4));
      await d.mount(
        screen: const VideoPlayerScreen(
          videoUrl: _url,
          title: 'P20 plain resume',
        ),
      );
      expect(_seeks(d.player), [const Duration(minutes: 4)]);
    } finally {
      await d.close();
    }
  });

  VideoPlayerScreen stremioTv({bool random = false}) => VideoPlayerScreen(
    videoUrl: _url,
    title: 'P20 Stremio TV',
    startAtPercent: .5,
    startFromRandom: random,
    randomStartMaxPercent: 10,
    stremioTvChannels: const [
      {'id': 'slot', 'name': 'P20 slot'},
    ],
    stremioTvCurrentChannelId: 'slot',
  );

  testWidgets(
    'P20 a Stremio TV percent start is deferred to the first duration and seeks exactly once',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: stremioTv());
        expect(_seeks(d.player), [const Duration(minutes: 10)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a Stremio TV random start is not deferred and seeks once inside the random share',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: stremioTv(random: true));
        final seeks = _seeks(d.player);
        expect(seeks, hasLength(1));
        expect(
          (seeks.first! as Duration) <= const Duration(minutes: 2),
          isTrue,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 one six-second autosave timer files the current position within a period',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      Future<int?> saved() async {
        final map = await d.f.finish(
          t,
          PlaybackStateStore.getPlaybackStateMap(),
        );
        return (map['video_p20_autosave'] as Map?)?['positionMs'] as int?;
      }

      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: _url,
            title: 'P20 autosave',
          ),
        );
        expect(
          d.periodic.where((p) => p == const Duration(seconds: 6)),
          hasLength(1),
        );
        Future<void> move(Duration to) async {
          d.player.state = d.player.state.copyWith(position: to);
          d.player.emit('position', to);
          await d.f.advance(t);
        }

        Future<Duration> untilSaved(int positionMs) async {
          var elapsed = Duration.zero;
          while (await saved() != positionMs) {
            expect(elapsed, lessThan(const Duration(seconds: 20)));
            await d.f.advance(t, const Duration(milliseconds: 100));
            elapsed += const Duration(milliseconds: 100);
          }
          return elapsed;
        }

        // Without any other save trigger, the periodic checkpoint files the
        // moved position within one period.
        await move(const Duration(minutes: 7));
        expect(
          await untilSaved(420000),
          lessThanOrEqualTo(const Duration(seconds: 6)),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a throwing direct (external-audio) open is logged and still arms the autosave',
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
            videoUrl: _url,
            title: 'P20 open throws',
            audioUrl: 'https://startup-open.test/audio.m4a',
          ),
        );
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        expect(
          d.logs.where(
            (l) => l.startsWith('VideoPlayer: initial open failed:'),
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a Stremio TV open that throws before completing fails its startup watch',
    (t) async {
      final d = EngineDriver(
        t,
        configurePlayer: (p) => p.failures['open'] = StateError('open failed'),
      );
      await d.initialize();
      try {
        await pumpScreen(d, stremioTv());
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(
          t,
          () => d.logs.any(
            (l) => l.startsWith('VideoPlayer: initial open failed:'),
          ),
        );
        await d.f.advance(t);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('No playable source could be started.'),
          ),
          findsWidgets,
        );
        expect(_seeks(d.player), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a failed ranked start reports the failure and never arms the autosave',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('p20-failed-only');
      d.openFailures[a.directUrl!] = StateError('source failed');
      try {
        await d.begin(
          d.screen(sources: [a], resolve: (s) async => s.directUrl),
        );
        await d.f.until(t, () => d.event('exhausted').isNotEmpty);
        await d.tick(const Duration(seconds: 1));
        expect(
          d.periodic.where((p) => p.$1 == const Duration(seconds: 6)),
          isEmpty,
        );
        await d.f.until(t, () => d.routeReturned);
      } finally {
        await d.close();
        // Leave the shared wakelock queue cursor in the real zone, as the
        // engine driver does, so later cases in this isolate do not stall.
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
    'P20 a screen closed while waiting for the video output never creates a player',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final held = await d.f.finish(t, VideoOutputLease.acquire());
      try {
        await pumpScreen(
          d,
          const VideoPlayerScreen(videoUrl: _url, title: 'P20 lease close'),
        );
        await d.f.advance(t, const Duration(seconds: 1));
        expect(d.f.players, isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
        held.release();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(d.f.players, isEmpty);
        expect(VideoOutputLease.isHeld, isFalse);
      } finally {
        held.release();
        await d.close();
      }
    },
  );

  final live = IptvChannel(
    name: 'P20 record live',
    url: 'https://startup-open.test/live.ts',
    contentType: 'live',
    group: 'News',
  );
  VideoPlayerScreen liveScreen() => VideoPlayerScreen(
    videoUrl: live.url,
    title: live.name,
    iptvChannels: [live],
    iptvStartIndex: 0,
  );

  for (final native in [true, false]) {
    testWidgets(
      'P20 recording is offered on a live channel only with a native backend native=$native',
      (t) async {
        final d = EngineDriver(t, native: native);
        await d.initialize();
        try {
          await d.mount(screen: liveScreen());
          expect(playerControls(t).hasRecord, native);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 a profile without the recordings feature is never offered Record',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        final active = (await d.f.finish(
          t,
          d.f.registry!.getProfile(ProfileRuntime.capture().profileId),
        ))!;
        ProfilePolicyGuard.updateActiveProfile(
          UserProfile(
            id: active.id,
            name: active.name,
            role: active.role,
            policy: ProfilePolicy(
              enabled: {...active.policy.enabled}
                ..remove(ProfileFeature.recordings),
            ),
            authorizationRevision: active.authorizationRevision,
            lifecycle: active.lifecycle,
            visibleDataGeneration: active.visibleDataGeneration,
            setupComplete: active.setupComplete,
            pinResetRequired: active.pinResetRequired,
            hasPin: active.hasPin,
            lockOnResume: active.lockOnResume,
            createdAt: active.createdAt,
            updatedAt: active.updatedAt,
          ),
        );
        await d.mount(screen: liveScreen());
        expect(playerControls(t).hasRecord, isFalse);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 an IPTV launch whose start index is out of range tunes as live',
    (t) async {
      final writes = <String>[];
      final d = EngineDriver(
        t,
        configurePlayer: (p) {
          (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
            if (name != 'setProperty') return;
            final (key, v) = value as (String, String);
            if (key == 'stream-lavf-o') writes.add(v);
          };
        },
      );
      await d.initialize();
      final vod = IptvChannel(
        name: 'P20 vod',
        url: 'https://startup-open.test/vod.mp4',
        contentType: 'vod',
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: vod.url,
            title: vod.name,
            iptvChannels: [vod],
            iptvStartIndex: 4,
          ),
        );
        expect(writes.first, startsWith('reconnect=1,reconnect_streamed=1,'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 an IPTV launch on an in-range VOD channel tunes as VOD', (
    t,
  ) async {
    final writes = <String>[];
    final d = EngineDriver(
      t,
      configurePlayer: (p) {
        (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
          if (name != 'setProperty') return;
          final (key, v) = value as (String, String);
          if (key == 'stream-lavf-o') writes.add(v);
        };
      },
    );
    await d.initialize();
    final vod = IptvChannel(
      name: 'P20 vod',
      url: 'https://startup-open.test/vod.mp4',
      contentType: 'vod',
    );
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: vod.url,
          title: vod.name,
          iptvChannels: [live, vod],
          iptvStartIndex: 1,
        ),
      );
      expect(writes.first, '');
    } finally {
      await d.close();
    }
  });
}
