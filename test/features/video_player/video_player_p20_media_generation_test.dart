import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/startup_driver.dart';
import 'support/stremio_tv_pick.dart';

final _wakeDrain = Object();

Future<void> _drainWake(WidgetTester t) => t.runAsync(
  () => PlayerDisplayControls.instance.setWakelockOwner(_wakeDrain, false),
);

VideoPlayerScreen _slot(String url) => VideoPlayerScreen(
  videoUrl: url,
  title: 'P20 generation slot',
  stremioTvChannels: stremioTvPickDirectory,
  stremioTvCurrentChannelId: 'a',
  stremioTvChannelSwitchProvider: stremioTvNoSwitch,
);

const _a = PlaylistEntry(url: 'https://generation.test/a.mp4', title: 'Gen A');
const _b = PlaylistEntry(url: 'https://generation.test/b.mp4', title: 'Gen B');
const _playlist = VideoPlayerScreen(
  videoUrl: 'https://generation.test/a.mp4',
  title: 'P20 generation playlist',
  disableAutoResume: true,
  startIndex: 0,
  playlist: [_a, _b],
);

/// Only the launch entry publishes a frame; the next entry stays frameless.
void _frameOnlyA(FakePlayer p) {
  final publish = p.onOpen;
  p.onOpen = () {
    if (p.state.playlist.medias.first.uri == _a.url) publish?.call();
  };
}

Future<void> _next(EngineDriver d) async {
  final dynamic callback = playerControls(d.t).onNext!;
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => callback()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'P20 a channel switch disposes the pending Stremio TV startup watch before the new open',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      try {
        await d.begin(_slot('https://generation.test/slot-a.mp4'));
        await d.openEntered();
        await d.tick(const Duration(seconds: 1));
        final watch = d.subscriptions.where((s) => s.owner == 'tv').toList();
        expect(watch, isNotEmpty, reason: 'the launch armed its startup watch');
        expect(watch.every((s) => !s.cancelled), isTrue);
        final switched = await beginStremioTvPick(t, d.f, 'b');
        await d.f.finish<dynamic>(t, switched);
        await d.tick();
        expect(d.opens.last, 'https://stremio-pick.test/b.mp4');
        expect(
          watch.every((s) => s.cancelled),
          isTrue,
          reason: 'the outgoing watch must not observe the new channel',
        );
        d.frame();
        await d.settle();
      } finally {
        await d.close();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 an unaccepted AIOStreams startup watch stops gating progress once a channel switch replaces it',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      try {
        await d.begin(_slot('https://aiostreams.generation.test/slot-a.mp4'));
        await d.openEntered();
        await d.tick(const Duration(seconds: 1));
        final switched = await beginStremioTvPick(t, d.f, 'b');
        await d.tick();
        d.frame();
        await d.f.finish<dynamic>(t, switched);
        await d.initialized();
        await d.tick(const Duration(seconds: 7));
        await d.settle();
        final saved = await d.f.finish(
          t,
          VideoProgressStorage.getVideoPlaybackState(videoTitle: 'Channel b'),
        );
        expect(
          saved,
          isNotNull,
          reason: 'the replaced watch no longer holds the validation gate',
        );
      } finally {
        await d.close();
        await _drainWake(t);
      }
    },
  );

  testWidgets(
    'P20 a media boundary drops the previous probe params: a decoder observer before new params probes nothing',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _frameOnlyA);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(androidRendererValidation: () => true));
      try {
        await d.mount(screen: _playlist);
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, isNotEmpty, reason: 'the launch was probed');
        expect(d.native.observers, contains('hwdec-current'));
        await _next(d);
        expect(d.player.state.playlist.medias.first.uri, _b.url);
        final lines = d.decoderLines.length;
        await d.native.observers['hwdec-current']!('mediacodec');
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines.skip(lines), isEmpty);
        d.player.publishFrame();
        d.f.controllers.last.publishFrame();
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines.skip(lines), isNotEmpty);
      } finally {
        VpS2Hooks.install(null);
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a media boundary resets the on-screen clock before the new media reports',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _frameOnlyA);
      await d.initialize();
      try {
        await d.mount(screen: _playlist);
        d.player.state = d.player.state.copyWith(
          duration: const Duration(minutes: 42, seconds: 10),
        );
        d.player.emit('duration', const Duration(minutes: 42, seconds: 10));
        await d.f.advance(t, const Duration(milliseconds: 300));
        expect(find.textContaining('42:10'), findsWidgets);
        await _next(d);
        expect(d.player.state.playlist.medias.first.uri, _b.url);
        expect(find.textContaining('42:10'), findsNothing);
      } finally {
        await d.close();
      }
    },
  );
}
