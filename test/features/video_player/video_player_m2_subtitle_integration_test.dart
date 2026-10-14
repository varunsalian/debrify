import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/fake_player.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/subtitle_streaming_http.dart';
import 'support/subtitle_sync_driver.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_apply_persistence_test.dart' show ApplyWrites;
import 'video_player_subtitle_edges_test.dart' show decoderError;
import 'video_player_subtitle_sync_overlay_test.dart' show offset;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;

const _screen = VideoPlayerScreen(
  videoUrl: 'https://player.test/m2-first.mp4',
  title: 'M2 subtitle integration',
  contentImdbId: 'tt1100001',
  contentType: 'movie',
  playlist: [
    PlaylistEntry(url: 'https://player.test/m2-first.mp4', title: 'First'),
    PlaylistEntry(url: 'https://player.test/m2-second.mp4', title: 'Second'),
  ],
);
const _key = 'video_m2_subtitle_integration';

void main() {
  testWidgets(
    'M2 one playback composes subtitle sync rollback sources policy renderer profiles and PiP',
    (t) async {
      final d = SubtitleSyncDriver(
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          (p.platform as FakeNativePlayer)
                  .properties['current-tracks/audio/lang'] =
              'fra';
        },
      );
      final f = d.fixture;
      final pip = PipLifecycleDriver(t, f, ios: true);
      final pipEntry = Completer<bool>();
      final alignment = CompletionDelivery(
        '_runAlignment',
        (v) => v is SubtitleAlignResult,
      );
      await d.initialize(t);
      final writes = (await t.runAsync(ApplyWrites.install))!;
      final a = ProfileRuntime.capture();
      pip.installPlatform();
      // Android renderer replacement and iOS subtitle visibility are exercised
      // through the independently proven S2/S2b predicates on the same State.
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => true));
      await f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      await f.finish(t, SubtitleSettingsStorage.setDefaultAudioLanguage('eng'));
      await f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('eng'),
      );
      await f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final transport = SubtitleStreamingHttp(f.network);
      HttpOverrides.global = transport;
      final bytes = utf8.encode(
        d
            .srt(d.speech())
            .replaceAll(
              'Dialogue line with a plausible length here',
              'Café — déjà vu, 日本語.',
            ),
      );
      final selectedFiles = <File>[];

      Future<File> choose(String id) async {
        final sub = StremioSubtitle(
          id: id,
          url: 'https://player.test/m2-$id.srt',
          lang: 'eng',
          source: 'M2 UTF-8 fixture',
        );
        transport.routes[sub.url] = () async => http.StreamedResponse(
          Stream.value(bytes),
          200,
          headers: {'content-type': 'application/x-subrip; charset=utf-8'},
        );
        final menu = await openPlayerMenu(t, f);
        expect(
          await f.finish(
            t,
            d.observe(() => menu.onAddonSubtitleSelected(sub, '1')),
          ),
          isTrue,
        );
        menu.onClose();
        await f.advance(t);
        final file = File(f.player.state.track.subtitle.id);
        expect(f.player.state.track.subtitle.uri, isTrue);
        expect(await t.runAsync(file.readAsBytes), bytes);
        expect(File('${file.path}.part').existsSync(), isFalse);
        expect(transport.closedFor(sub.url), hasLength(1));
        selectedFiles.add(file);
        return file;
      }

      Future<SubtitleLinePickerOverlay> showSync() async {
        final menu = await openPlayerMenu(t, f);
        menu.onClose();
        menu.onSyncRequested!();
        await f.advance(t);
        expect(find.byType(SubtitleLinePickerOverlay), findsOneWidget);
        return t.widget<SubtitleLinePickerOverlay>(
          find.byType(SubtitleLinePickerOverlay),
        );
      }

      Future<void> style(int color, int elevation) async {
        await f.finish(
          t,
          SubtitleSettingsService.instance.setColorIndex(color),
        );
        await f.finish(
          t,
          SubtitleSettingsService.instance.setElevationIndex(elevation),
        );
        final settings = await f.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        final menu = await openPlayerMenu(t, f);
        d.observe(() => menu.onSubtitleStyleChanged!(settings));
        menu.onClose();
        await f.advance(t);
      }

      mkv.SubtitleViewConfiguration rendered() => t
          .widget<mkv.Video>(find.byType(mkv.Video).first)
          .subtitleViewConfiguration;

      try {
        await d.mount(t, screen: _screen);
        final owner = t.state(find.byType(VideoPlayerScreen));
        await f.actions.settle(t);
        expect(f.player.state.track.subtitle.id, '2');
        expect(rendered().visible, isTrue);
        // sid is the deliberately separate authoritative native readback;
        // FakePlayer's optimistic Dart selection must not overwrite it.
        expect(d.native.properties['sid'], 'no');
        expect(d.native.calls, contains(('setProperty', ('sid', 'no'))));

        final initial = await choose('aligned');
        await d.feed(t);
        await f.advance(t, const Duration(seconds: 8));
        await f.until(t, () => d.pill?.phase == AutoSyncPillPhase.synced);
        expect(d.native.properties['sub-delay'], '2.114');
        expect(d.native.properties['sub-visibility'], 'no');
        expect(
          await f.finish(t, SubtitleSettingsService.instance.getSyncOffsetMs()),
          2114,
        );
        final aligned = await showSync();
        expect(aligned.subtitleFilePath, initial.path);
        expect(aligned.currentOffsetMs, 2114);
        // A nonzero session offset gates the real ladder; explicitly return
        // timing to zero through the public overlay before the next alignment.
        await offset(t, d, aligned.onOffsetChanged, 0);
        expect(d.native.properties['sub-delay'], '0.000');
        aligned.onDismiss();
        await f.advance(t);

        final manual = await alignment.run(() => choose('manual'));
        await d.feed(t);
        await f.advance(t, const Duration(seconds: 8));
        await f.until(t, () => alignment.pending.isNotEmpty);
        expect(d.pill?.phase, AutoSyncPillPhase.checking);
        final overlay = await showSync();
        expect(overlay.subtitleFilePath, manual.path);
        await offset(t, d, overlay.onOffsetChanged, 900);
        expect(d.pill, isNull);
        expect(d.native.properties['sub-delay'], '0.900');
        expect(alignment.pending, hasLength(1));
        alignment.release();
        await f.actions.settle(t);
        expect(
          await f.finish(t, SubtitleSettingsService.instance.getSyncOffsetMs()),
          900,
        );
        expect(d.native.properties['sub-delay'], '0.900');
        expect(
          t
              .widget<SubtitleLinePickerOverlay>(
                find.byType(SubtitleLinePickerOverlay),
              )
              .currentOffsetMs,
          900,
        );
        overlay.onDismiss();
        await f.advance(t);

        final rejected = await choose('rejected');
        expect(rejected.path, isNot(manual.path));
        f.player.emit('log', decoderError);
        await f.until(t, () => f.player.state.track.subtitle.id == manual.path);
        await f.until(t, () => d.logs.any((v) => v.contains('user notified')));
        await f.actions.settle(t);
        final restored = await showSync();
        expect(restored.subtitleFilePath, manual.path);
        expect(restored.currentOffsetMs, 900);
        expect(
          (await writes.map(a))[_key]['trackPreferences']['subtitleTrackId'],
          'stremio:manual',
        );
        expect(
          (await writes.map(a))[_key]['trackPreferences']['audioTrackId'],
          '1',
        );
        expect(selectedFiles.every((file) => file.existsSync()), isTrue);
        restored.onDismiss();
        await f.advance(t);

        // Remove the explicit saved choice before the actual content reset.
        // That caller also resets the route's manual-choice flag; otherwise
        // the policy change below would intentionally preserve manual choice.
        await f.finish(
          t,
          PlaybackStateStore.savePlaybackStateMap({
            'ownerA': {'value': 'A'},
          }),
        );
        final dynamic next = playerControls(t).onNext;
        final dynamic reset = d.observe<dynamic>(() => next());
        if (reset is Future) await f.finish<dynamic>(t, reset);
        await f.until(
          t,
          () => f.player.calls.where((v) => v.$1 == 'open').length == 2,
        );
        await f.actions.settle(t);
        expect(selectedFiles.every((file) => !file.existsSync()), isTrue);
        expect(
          await f.finish(t, SubtitleSettingsService.instance.getSyncOffsetMs()),
          0,
        );
        expect(d.native.properties['sub-delay'], '0.000');
        final resetMenu = await openPlayerMenu(t, f);
        resetMenu.onClose();
        resetMenu.onSyncRequested!();
        await f.advance(t);
        expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
        final stepper = t.widget<SyncStepperOverlay>(
          find.byType(SyncStepperOverlay),
        );
        expect(stepper.offsetMs, 0);
        stepper.onDismiss();
        await f.advance(t);

        var menu = await openPlayerMenu(t, f);
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        await f.finish(
          t,
          d.observe(() => menu.onAudioSelected('1', menu.selectedSubtitleId)),
        );
        await f.actions.settle(t);
        expect(f.player.state.track.subtitle.id, 'no');
        expect(d.native.properties['sub-visibility'], 'no');
        d.native.properties['current-tracks/audio/lang'] = 'fra';
        await f.finish(t, d.observe(() => menu.onAudioSelected('2', 'no')));
        await f.actions.settle(t);
        expect(f.player.state.track.subtitle.id, '2');
        expect(
          (await writes.map(a))[_key]['trackPreferences']['subtitleTrackId'],
          'auto',
        );
        expect(
          (await writes.map(a))[_key]['trackPreferences']['audioTrackId'],
          '2',
        );
        menu.onClose();
        await f.advance(t);

        final old = f.player;
        old.state = old.state.copyWith(position: Duration.zero);
        old.emit('position', Duration.zero);
        await f.advance(t);
        old.emit('error', 'synthetic MediaCodec video output failure');
        await f.until(t, () => f.players.length == 2);
        f.player.deliverReady();
        await f.until(t, () => f.player.calls.any((v) => v.$1 == 'open'));
        await f.until(
          t,
          () =>
              d.logs.where((v) => v.contains('controller installed')).length ==
              2,
        );
        await f.actions.settle(t);
        expect(old.disposed.isCompleted, isTrue);
        expect(t.state(find.byType(VideoPlayerScreen)), same(owner));
        expect((old.platform as FakeNativePlayer).mapObservers, isEmpty);
        final replacement = await choose('fresh-engine');
        await d.feed(t);
        await f.advance(t, const Duration(seconds: 8));
        await f.until(t, () => d.pill?.phase == AutoSyncPillPhase.synced);
        expect(d.native.properties['sub-delay'], '2.114');
        expect(d.native.properties['sid'], 'no');
        expect(rendered().visible, isTrue);
        await style(1, 3);
        expect(rendered().style.color, const Color(0xFFFFFF00));
        expect(rendered().padding.bottom, 180);
        expect(d.native.properties['sub-delay'], '2.114');
        expect(await writes.physical(a, 'subtitle_color_index'), 1);
        expect(await writes.physical(a, 'subtitle_elevation_index'), 3);
        final aFinal = await writes.map(a);
        expect(
          aFinal[_key]['trackPreferences']['subtitleTrackId'],
          'stremio:fresh-engine',
        );
        expect(aFinal['ownerA'], {'value': 'A'});

        await incomingProfile(t, f);
        final b = ProfileRuntime.capture();
        expect(b.profileId, isNot(a.profileId));
        await f.finish(
          t,
          PlaybackStateStore.savePlaybackStateMap({
            'ownerB': {'value': 'B'},
          }),
        );
        final incoming = await choose('incoming-profile');
        final incomingOverlay = await showSync();
        expect(incomingOverlay.subtitleFilePath, incoming.path);
        await offset(t, d, incomingOverlay.onOffsetChanged, -450);
        expect(d.native.properties['sub-delay'], '-0.450');
        expect(
          t
              .widget<SubtitleLinePickerOverlay>(
                find.byType(SubtitleLinePickerOverlay),
              )
              .currentOffsetMs,
          -450,
        );
        incomingOverlay.onDismiss();
        await f.advance(t);
        await style(2, 1);
        expect(rendered().style.color, const Color(0xFF00FFFF));
        expect(rendered().padding.bottom, 80);
        expect(d.native.properties['sub-delay'], '-0.450');
        expect(await writes.physical(a, 'subtitle_color_index'), 1);
        expect(await writes.physical(a, 'subtitle_elevation_index'), 3);
        expect(await writes.physical(b, 'subtitle_color_index'), 2);
        expect(await writes.physical(b, 'subtitle_elevation_index'), 1);
        expect(await writes.map(a), aFinal);
        final bFinal = await writes.map(b);
        expect(bFinal['ownerB'], {'value': 'B'});
        expect(
          bFinal[_key]['trackPreferences']['subtitleTrackId'],
          'stremio:incoming-profile',
        );
        expect(bFinal[_key]['trackPreferences']['audioTrackId'], '1');
        expect(await writes.physical(a, 'subtitle_auto_sync_enabled'), isTrue);
        expect(await writes.physical(b, 'subtitle_auto_sync_enabled'), isNull);

        // The retained PiP caller crosses P8 -> P10 while P9/P11's selected
        // path and session offset remain live on the replacement player.
        pip.handler = (call) => call.method == 'enterPip'
            ? pipEntry.future
            : call.method == 'isSupported'
            ? true
            : null;
        final dynamic enter = playerControls(t).onPip;
        var entered = false;
        final Future<void> entry = pip.observe(() => enter() as Future<void>);
        entry.then((_) => entered = true);
        await f.until(t, () => pip.named('enterPip').isNotEmpty);
        expect(entered, isFalse);
        expect(pipEntry.isCompleted, isFalse);
        expect(d.native.properties['sub-visibility'], 'yes');
        expect(pip.named('enterPip'), hasLength(1));
        expect(rendered().visible, isFalse);
        await pip.deliver('onPipModeChanged', true);
        pipEntry.complete(true);
        await f.finish(t, entry);
        expect(entered, isTrue);
        expect(d.native.properties['sub-visibility'], 'yes');
        expect(rendered().visible, isFalse);
        await pip.deliver('onPipModeChanged', false);
        expect(d.native.properties['sub-visibility'], 'no');
        expect(rendered().visible, isTrue);
        expect(d.native.properties['sub-delay'], '-0.450');
        expect(rendered().style.color, const Color(0xFF00FFFF));
        expect(rendered().padding.bottom, 80);
        expect(d.native.properties['sid'], 'no');
        expect(f.player.state.track.subtitle.id, incoming.path);
        expect(replacement.existsSync(), isTrue);
        expect(incoming.existsSync(), isTrue);
        expect(await writes.map(a), aFinal);
        expect(await writes.map(b), bFinal);
        expect(d.errors, isEmpty);
        expect(pip.errors, isEmpty);
        await pip.retire();
        expect(selectedFiles.every((file) => !file.existsSync()), isTrue);
        expect(f.directory.existsSync(), isTrue);
      } finally {
        alignment.release();
        if (!pipEntry.isCompleted) pipEntry.complete(false);
        await pip.close();
        debugPrint = d.oldPrint;
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
