import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/startup_driver.dart' show startupSource;
import 'support/stremio_tv_pick.dart';

const _cold = 'https://dl.mypikpak.com/p20-continuation.mp4';
const _restoreEntered = 'SubAuto: _restoreTrackPreferences entered';
const _committed = 'SourceSelect: event=player_source_committed ';

List<String> _lines(EngineDriver d, String prefix) => [
  for (final l in d.logs)
    if (l.startsWith(prefix)) l,
];

/// Cold-storage media never reports metadata; any other URL publishes as usual.
void Function(FakePlayer) _coldStaysDark({int? onlyPlayer}) {
  var created = 0;
  return (p) {
    final index = created++;
    final publish = p.onOpen;
    p.onOpen = () {
      final dark =
          p.state.playlist.medias.first.uri == _cold &&
          (onlyPlayer == null || onlyPlayer == index);
      if (!dark) publish?.call();
    };
  };
}

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P20 a cancelled PikPak retry commits no launch source and never restores the next channel',
    (t) async {
      final commits = <String>[];
      final source = startupSource('p20-pikpak-cancelled', url: _cold);
      final d = EngineDriver(t, configurePlayer: _coldStaysDark());
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _cold,
            title: 'P20 PikPak cancelled',
            stremioSources: [source],
            stremioCurrentSourceIndex: 0,
            onStremioSourceCommitted: (s) async => commits.add(s.name),
            stremioTvChannels: stremioTvPickDirectory,
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: stremioTvNoSwitch,
          ),
        );
        expect(
          d.logs.where(
            (l) => l.startsWith('PikPak: _playPikPakVideoWithRetry called'),
          ),
          hasLength(1),
        );
        final restoresBefore = _lines(d, _restoreEntered).length;
        final switched = await beginStremioTvPick(
          t,
          d.f,
          'b',
          observe: d.observe,
        );
        await d.f.finish<dynamic>(t, switched);
        await d.f.advance(t, const Duration(seconds: 3));
        await d.f.actions.settle(t);
        expect(
          d.logs.where((l) => l.startsWith('PikPak: Retry cancelled')),
          isNotEmpty,
          reason: 'the switch cancelled the cold-storage retry',
        );
        expect(commits, isEmpty);
        expect(_lines(d, _committed), isEmpty);
        expect(_lines(d, _restoreEntered).length, restoresBefore);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a screen closed during the PikPak start seek restores no track preferences',
    (t) async {
      final seek = Completer<void>();
      final d = EngineDriver(
        t,
        configurePlayer: (p) => p.delays['seek'] = seek,
      );
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: _cold,
            title: 'P20 PikPak closed',
            startAtPercent: .25,
            playlist: [
              PlaylistEntry(
                url: _cold,
                title: 'Cold.Closed.mkv',
                provider: 'pikpak',
              ),
            ],
          ),
          settleInitialization: false,
        );
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'seek'));
        expect(_lines(d, _restoreEntered), isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.advance(t, const Duration(milliseconds: 200));
        seek.complete();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_lines(d, _restoreEntered), isEmpty);
      } finally {
        if (!seek.isCompleted) seek.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a PikPak continuation outlived by a renderer rebuild leaves the rebuilt player to the fallback',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _coldStaysDark(onlyPlayer: 0));
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
            videoUrl: _cold,
            title: 'P20 PikPak rebuilt',
            playlist: [
              PlaylistEntry(
                url: _cold,
                title: 'Cold.Rebuilt.mkv',
                provider: 'pikpak',
              ),
            ],
          ),
        );
        expect(_lines(d, _restoreEntered), isEmpty);
        d.player.emit('error', 'fixture MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
        await d.f.advance(t, const Duration(seconds: 3));
        await d.f.actions.settle(t);
        expect(d.player.state.duration, greaterThan(Duration.zero));
        expect(
          _lines(d, _restoreEntered),
          hasLength(1),
          reason: 'only the fallback restores tracks on the rebuilt player',
        );
        expect(_lines(d, _committed), isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
