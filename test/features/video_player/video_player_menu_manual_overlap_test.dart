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
    'p13 failed old manual choice cannot restore policy during a reopened menu choice',
    (t) async {
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p, sid: '3');
          (p.platform as FakeNativePlayer)
                  .properties['current-tracks/audio/lang'] =
              'fra';
        },
      );
      await d.setup();
      final aGate = Completer<void>();
      final bGate = Completer<void>();
      Future<bool>? a;
      Future<bool>? b;
      var aHeld = false;
      var bHeld = false;
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
            videoUrl: 'https://player.test/manual-overlap.mp4',
            title: 'Manual overlap',
          ),
          publishTracks: false,
        );
        await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
        await d.f.actions.settle(t);
        d.player.heldOperation = (name, value) =>
            name == 'subtitle' &&
            value is mk.SubtitleTrack &&
            ((value.id == '3' && !aGate.isCompleted) ||
                (value.id == '1' && !bGate.isCompleted));
        d.player.beforeOperation = (name, value) async {
          if (name != 'subtitle' || value is! mk.SubtitleTrack) return;
          if (value.id == '3' && !aHeld) {
            aHeld = true;
            await aGate.future;
            throw StateError('old manual selection failed');
          }
          if (value.id == '1' && !bHeld) {
            bHeld = true;
            await bGate.future;
          }
        };
        final first = await d.menu();
        a = d.observe(() => first.onEmbeddedSubtitleSelected('3', '2'));
        await d.f.until(t, () => aHeld);
        first.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final second = await d.menu();
        b = d.observe(() => second.onEmbeddedSubtitleSelected('1', '2'));
        await d.f.until(t, () => bHeld);
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        aGate.complete();
        expect(await d.f.finish(t, a!), isFalse);
        await d.f.actions.settle(t);
        expect(
          d.player.state.track.subtitle.id,
          '2',
          reason:
              'old failure cannot resume automatic off while B remains pending',
        );
        bGate.complete();
        expect(await d.f.finish(t, b!), isTrue);
        expect(d.player.state.track.subtitle.id, '1');
        expect(d.errors, isEmpty);
      } finally {
        if (!aGate.isCompleted) aGate.complete();
        if (!bGate.isCompleted) bGate.complete();
        if (a != null) await d.f.finish(t, a);
        if (b != null) await d.f.finish(t, b);
        await d.close();
      }
    },
  );
}
