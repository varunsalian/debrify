import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  TraktTestTransport.install();
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P19 a failed rebuild of a pending Stremio TV start cancels its slot seek',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      final a = startupSource('watch-seek-failed', addon: 'AIOStreams');
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P19 failed renderer slot seek',
            startAtPercent: .25,
            stremioSources: [a],
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P19 TV'},
            ],
            stremioTvCurrentChannelId: 'slot',
          ),
        );
        await d.openEntered();
        d.openFailures[a.directUrl!] = StateError(
          'fixture renderer reopen failure',
        );
        d.player.emit('error', 'fixture MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.openEntered(2);
        await d.f.until(
          t,
          () => find
              .text('No playable source could be started.')
              .evaluate()
              .isNotEmpty,
        );
        // Media metadata arriving now must not run the failed start's seek.
        d.frame();
        await d.tick(const Duration(seconds: 1));
        expect(d.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        await d.f.until(t, () => d.routeReturned);
      } finally {
        await d.close();
      }
    },
  );
}
