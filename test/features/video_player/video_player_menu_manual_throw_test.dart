import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;

void main() {
  testWidgets(
    'p13 thrown manual apply restores automatic policy before propagating its error',
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
      final priorPrint = debugPrint;
      var throwOnce = true;
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
            videoUrl: 'https://player.test/manual-throw.mp4',
            title: 'Manual throw',
          ),
          publishTracks: false,
        );
        await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
        await d.f.actions.settle(t);
        final menu = await d.menu();
        d.player.beforeOperation = (name, value) {
          if (name == 'subtitle' &&
              value is mk.SubtitleTrack &&
              value.id == '3') {
            throw StateError('fixture manual setter failed');
          }
        };
        debugPrint = (message, {wrapWidth}) {
          if (throwOnce &&
              message != null &&
              message.contains(
                '[SubtitleDiag] set FAILED source=player-menu-embedded',
              )) {
            throwOnce = false;
            throw StateError('fixture diagnostic sink failed');
          }
          priorPrint(message, wrapWidth: wrapWidth);
        };
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        Object? caught;
        final done = d.observe(
          () => menu
              .onEmbeddedSubtitleSelected('3', '2')
              .then<void>(
                (_) => fail('the original error must propagate'),
                onError: (Object error, StackTrace stack) {
                  caught = error;
                },
              ),
        );
        await d.f.finish(t, done);
        expect(
          caught,
          isA<StateError>().having(
            (error) => error.message,
            'source error',
            'fixture diagnostic sink failed',
          ),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.id == 'no');
        expect(d.errors, isEmpty);
      } finally {
        debugPrint = priorPrint;
        await d.close();
      }
    },
  );
}
