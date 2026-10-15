import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;

void main() {
  testWidgets(
    'p13 pending manual menu choice blocks automatic off during an audio menu refresh',
    (t) async {
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (player) {
          seedLanguagePlayer(player, sid: '3');
          (player.platform as FakeNativePlayer)
                  .properties['current-tracks/audio/lang'] =
              'fra';
        },
      );
      await d.setup();
      final gate = Completer<void>();
      Future<bool>? pending;
      var held = false;
      try {
        await d.order(language: 'eng', embeddedFirst: true);
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
        );
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/manual-pending.mp4',
            title: 'Manual pending',
          ),
          publishTracks: false,
        );
        await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
        await d.f.actions.settle(t);
        d.player.heldOperation = (name, value) =>
            name == 'subtitle' &&
            value is mk.SubtitleTrack &&
            value.id == '3' &&
            !gate.isCompleted;
        d.player.beforeOperation = (name, value) async {
          if (d.player.heldOperation!(name, value)) {
            held = true;
            await gate.future;
          }
        };
        final menu = await d.menu();
        pending = d.observe(() => menu.onEmbeddedSubtitleSelected('3', '2'));
        await d.f.until(t, () => held);
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        await d.f.finish(t, d.observe(() => menu.onAudioSelected('1', '2')));
        await d.f.actions.settle(t);
        expect(gate.isCompleted, isFalse);
        expect(d.player.state.track.subtitle.id, '2');
        gate.complete();
        expect(await d.f.finish(t, pending!), isTrue);
        expect(d.player.state.track.subtitle.id, '3');
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        if (pending != null) await d.f.finish(t, pending);
        await d.close();
      }
    },
  );
}
