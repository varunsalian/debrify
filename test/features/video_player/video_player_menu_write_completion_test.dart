import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_persistence_test.dart'
    show ApplyWrites, preferenceKey;

void main() {
  testWidgets(
    'p13 menu audio callback awaits the player setter before completing',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final gate = Completer<void>();
      Future<void>? pending;
      var held = false;
      var complete = false;
      try {
        await d.mount();
        final menu = await d.menu();
        d.player.heldOperation = (name, value) =>
            name == 'audio' &&
            value is mk.AudioTrack &&
            value.id == '2' &&
            !gate.isCompleted;
        d.player.beforeOperation = (name, value) async {
          if (d.player.heldOperation!(name, value)) {
            held = true;
            await gate.future;
          }
        };
        pending = d.observe(() => menu.onAudioSelected('2', '1'));
        pending!.then<void>((_) => complete = true);
        await d.f.until(t, () => held);
        await d.f.actions.settle(t);
        expect(d.player.state.track.audio.id, '1');
        expect(complete, isFalse);
        gate.complete();
        await d.f.finish(t, pending);
        expect(d.player.state.track.audio.id, '2');
        expect(complete, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        if (pending != null) await d.f.finish(t, pending);
        await d.close();
      }
    },
  );
  for (final action in ['audio', 'subtitle-off', 'addon']) {
    testWidgets(
      'p13 menu $action callback remains pending until its physical preference write completes',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final store = await t.runAsync(ApplyWrites.install);
        final scope = ProfileRuntime.capture();
        try {
          await d.mount();
          final menu = await d.menu();
          const subtitle = StremioSubtitle(
            id: 'p13-write',
            url: 'https://player.test/write.srt',
            lang: 'eng',
            source: 'Write fixture',
          );
          d.f.network.replies[subtitle.url] = http.Response(
            '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
            200,
          );
          store!.armed = true;
          var complete = false;
          final pending = action == 'audio'
              ? d.observe(() => menu.onAudioSelected('2', '1'))
              : action == 'subtitle-off'
              ? d.observe(() => menu.onSubtitlesOff('2'))
              : d.observe(() => menu.onAddonSubtitleSelected(subtitle, '2'));
          pending.then<void>((_) => complete = true);
          await d.f.until(t, () => store.pending.length == 1);
          await d.f.actions.settle(t);
          expect(store.pending.single.gate.isCompleted, isFalse);
          expect(complete, isFalse);
          store.armed = false;
          store.release(0);
          await d.f.finish(t, pending);
          expect(complete, isTrue);
          expect(
            (await store.map(scope))[preferenceKey]['trackPreferences'],
            containsPair('audioTrackId', '2'),
          );
          expect(d.errors, isEmpty);
        } finally {
          store!.releaseAll();
          await d.close();
        }
      },
    );
  }
}
