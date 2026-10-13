import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:http/http.dart' as http;

import 'support/fake_player.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/player_actions.dart';
import 'video_player_subtitle_edges_test.dart' show decoderError;
import 'support/subtitle_sync_driver.dart';
import 'video_player_subtitle_sync_overlay_test.dart' show offset;

void main() {
  testWidgets(
    'subtitle late decoder rollback restores the previous external path and reactivates the real engine',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t, id: 'rollback-original', caption: 'Short caption.');
        await d.feed(t, durationMs: 1000);
        final previous = d.fixture.player.state.track.subtitle.id;
        await d.select(t, id: 'rollback-rejected', caption: 'Short caption.');
        await d.feed(t, durationMs: 1000);
        expect(d.fixture.player.state.track.subtitle.id, isNot(previous));
        final removes = d.filterCommands.where((v) => v[1] == 'remove').length;
        d.fixture.player.emit('log', decoderError);
        await d.fixture.until(
          t,
          () => d.fixture.player.state.track.subtitle.id == previous,
        );
        await d.fixture.until(
          t,
          () =>
              d.filterCommands.where((v) => v[1] == 'remove').length > removes,
        );
        await d.fixture.until(
          t,
          () => d.logs.where((v) => v.contains('Trying to sync')).length == 3,
        );
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        expect(
          t
              .widget<SubtitleLinePickerOverlay>(
                find.byType(SubtitleLinePickerOverlay),
              )
              .subtitleFilePath,
          previous,
        );
        expect(d.pill?.phase, AutoSyncPillPhase.announce);
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );

  testWidgets(
    'subtitle content replacement clears timing and path but a saved line callback targets the new playback',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(
          t,
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/sub-item1.mp4',
            title: 'Subtitle item one',
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/sub-item1.mp4',
                title: 'Subtitle item one',
              ),
              PlaylistEntry(
                url: 'https://player.test/sub-item2.mp4',
                title: 'Subtitle item two',
              ),
            ],
          ),
        );
        await d.select(t, caption: 'Short caption.');
        await d.feed(t, durationMs: 1000);
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        final saved = t.widget<SubtitleLinePickerOverlay>(
          find.byType(SubtitleLinePickerOverlay),
        );
        final oldPath = saved.subtitleFilePath;
        await offset(t, d, saved.onOffsetChanged, 500);
        saved.onDismiss();
        await d.fixture.advance(t);
        final dynamic next = playerControls(t).onNext;
        final dynamic pending = d.observe<dynamic>(() => next());
        if (pending is Future) await d.fixture.finish<dynamic>(t, pending);
        await d.fixture.until(
          t,
          () => d.fixture.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.fixture.actions.settle(t);
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          0,
        );
        expect(d.native.properties['sub-delay'], '0.000');
        final incoming = await openPlayerMenu(t, d.fixture);
        incoming.onClose();
        incoming.onSyncRequested!();
        await d.fixture.advance(t);
        expect(find.byType(SyncStepperOverlay), findsOneWidget);
        expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
        d.fixture.player.state = d.fixture.player.state.copyWith(
          position: const Duration(seconds: 9),
        );
        d.fixture.player.emit('position', d.fixture.player.state.position);
        await d.fixture.advance(t);
        expect(saved.subtitleFilePath, oldPath);
        expect(saved.getCurrentPositionMs(), 9000);
        await offset(t, d, saved.onOffsetChanged, 777);
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          777,
        );
        expect(d.native.properties['sub-delay'], '0.777');
        expect(
          t
              .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
              .offsetMs,
          777,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
  for (final event in [
    'small position',
    'seek jump',
    'same audio',
    'new audio',
  ]) {
    testWidgets(
      'subtitle held alignment handles the retained $event subscription',
      (t) async {
        final d = SubtitleSyncDriver();
        final held = CompletionDelivery(
          '_runAlignment',
          (v) => v is SubtitleAlignResult,
        );
        await d.initialize(t);
        try {
          await d.mount(t);
          await held.run(() => d.select(t));
          await d.feed(t);
          await d.fixture.advance(t, const Duration(seconds: 8));
          await d.fixture.until(t, () => held.pending.isNotEmpty);
          expect(d.pill?.phase, AutoSyncPillPhase.checking);
          if (event.contains('position') || event == 'seek jump') {
            final position = Duration(
              milliseconds: event == 'seek jump' ? 10000 : 500,
            );
            d.fixture.player.state = d.fixture.player.state.copyWith(
              position: position,
            );
            d.fixture.player.emit('position', position);
          } else {
            await d.observe(
              () => d.fixture.player.setAudioTrack(
                event == 'new audio'
                    ? const mk.AudioTrack('2', 'French', 'fra')
                    : d.fixture.player.state.track.audio,
              ),
            );
          }
          await d.fixture.advance(t);
          expect(held.pending, hasLength(1));
          held.release();
          await d.fixture.advance(t);
          final retired = event == 'seek jump' || event == 'new audio';
          if (retired) {
            expect(d.native.properties['sub-delay'], isNull);
            expect(
              d.logs.where((v) => v.contains('Subtitles synced')),
              isEmpty,
            );
            if (event == 'new audio') {
              await d.fixture.until(
                t,
                () => d.pill?.phase == AutoSyncPillPhase.announce,
              );
            } else {
              expect(d.pill?.phase, AutoSyncPillPhase.checking);
            }
          } else {
            await d.fixture.until(
              t,
              () => d.pill?.phase == AutoSyncPillPhase.synced,
            );
            expect(d.native.properties['sub-delay'], '1.869');
          }
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          await d.close(t);
        }
      },
    );
  }
  testWidgets(
    'subtitle replacement clears the disposed engine before incoming audio setup and a saved selection',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        'configurePlayerAudio',
        (v) => v == null && d.fixture.players.length == 2,
      );
      await d.initialize(t);
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      await d.fixture.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      try {
        await held.run(() => d.mount(t));
        final menu = await d.select(t);
        await d.feed(t, durationMs: 1000);
        final old = d.fixture.player;
        old.state = old.state.copyWith(position: Duration.zero);
        old.emit('position', Duration.zero);
        await d.fixture.advance(t);
        old.emit('error', 'synthetic MediaCodec video output failure');
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        expect(old.disposed.isCompleted, isTrue);
        expect(d.fixture.players, hasLength(2));
        expect(
          d.logs.where((v) => v.contains('controller installed')),
          hasLength(1),
        );
        d.fixture.player.deliverReady();
        const subtitle = StremioSubtitle(
          id: 'renderer-early',
          url: 'https://player.test/renderer-early.srt',
          lang: 'eng',
          source: 'Early replacement',
        );
        d.fixture.network.replies[subtitle.url] = http.Response(
          d.srt(d.speech()),
          200,
        );
        expect(
          await d.fixture.finish(
            t,
            menu.onAddonSubtitleSelected(subtitle, '1'),
          ),
          isTrue,
        );
        expect(
          d.logs
              .where((v) => v.startsWith('SubtitleAutoSync: external subtitle'))
              .last,
          'SubtitleAutoSync: external subtitle set (controller=MISSING)',
        );
        expect(held.pending, hasLength(1));
        held.release();
        await d.fixture.until(
          t,
          () => d.fixture.player.calls.any((c) => c.$1 == 'open'),
        );
        expect(
          d.logs.where((v) => v.contains('controller installed')),
          hasLength(2),
        );
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
        VpS2Hooks.install(null);
      }
    },
  );

  for (final boundary in ['subtitle change', 'disposal']) {
    testWidgets(
      'subtitle pending filter removal across $boundary preserves the lifecycle queue',
      (t) async {
        final d = SubtitleSyncDriver(fileTransport: true);
        final gate = Completer<void>();
        await d.initialize(t);
        try {
          await d.mount(t);
          await d.select(t);
          await d.installedFile(t);
          final native = d.native;
          native.heldOperation = (n, v) =>
              n == 'command' && (v as List<String>)[1] == 'remove';
          native.beforeOperation = (n, v) =>
              native.heldOperation!(n, v) ? gate.future : null;
          final menu = await openPlayerMenu(t, d.fixture);
          expect(await d.fixture.finish(t, menu.onSubtitlesOff('1')), isTrue);
          menu.onClose();
          await d.fixture.until(
            t,
            () => d.filterCommands.any((c) => c[1] == 'remove'),
          );
          final adds = d.filterCommands.where((c) => c[1] == 'add').length;
          if (boundary == 'subtitle change') {
            await d.select(t, id: 'queued-after-removal');
            expect(
              d.filterCommands.where((c) => c[1] == 'add'),
              hasLength(adds),
            );
            expect(d.pill, isNull);
          } else {
            await d.observe(() => t.pumpWidget(const SizedBox()));
            expect(d.fixture.player.disposed.isCompleted, isFalse);
            expect(VideoOutputLease.isHeld, isTrue);
          }
          expect(gate.isCompleted, isFalse);
          gate.complete();
          if (boundary == 'subtitle change') {
            await d.fixture.until(
              t,
              () => d.pill?.phase == AutoSyncPillPhase.announce,
            );
            expect(
              d.filterCommands.where((c) => c[1] == 'add'),
              hasLength(adds + 1),
            );
          } else {
            await d.fixture.until(
              t,
              () => d.fixture.player.disposed.isCompleted,
            );
            expect(VideoOutputLease.isHeld, isFalse);
          }
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await d.close(t);
        }
      },
    );
  }
  testWidgets(
    'subtitle selected before engine installation remains inactive even when the same path is selected again',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery('configurePlayerAudio', (v) => v == null);
      await d.initialize(t);
      try {
        d.timerTester = t;
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await held.run(
          () => d.observe(
            () => t.pumpWidget(
              MaterialApp(
                navigatorKey: d.fixture.navigator,
                theme: ThemeData.dark(),
                home: SubtitleSyncDriver.screen,
              ),
            ),
          ),
        );
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        expect(d.fixture.players, hasLength(1));
        d.fixture.player.deliverReady();
        await d.fixture.advance(t);
        expect(
          d.logs.where((v) => v.contains('controller installed')),
          isEmpty,
        );
        await d.select(t);
        expect(d.logs.join('\n'), contains('controller=MISSING'));
        expect(d.filterCommands, isEmpty);
        held.release();
        await d.fixture.until(
          t,
          () => d.fixture.player.calls.any((c) => c.$1 == 'open'),
        );
        await d.fixture.advance(t);
        expect(
          d.logs.where((v) => v.contains('controller installed')),
          hasLength(1),
        );
        expect(d.filterCommands, isEmpty);
        await d.select(t);
        expect(d.filterCommands, isEmpty);
        await d.select(t, id: 'different-path');
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.announce,
        );
        expect(d.filterCommands.where((c) => c[1] == 'add'), hasLength(2));
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );

  for (final boundary in [
    'subtitle change',
    'disposal',
    'renderer replacement',
  ]) {
    testWidgets(
      'subtitle real alignment held across $boundary cannot apply the retired result',
      (t) async {
        final d = SubtitleSyncDriver();
        final held = CompletionDelivery(
          '_runAlignment',
          (v) => v is SubtitleAlignResult,
        );
        await d.initialize(t);
        try {
          if (boundary == 'renderer replacement') {
            VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
            await d.fixture.finish(
              t,
              PlayerSettingsStorage.setAndroidVideoRendererMode(
                AndroidVideoRendererMode.directSurface,
              ),
            );
          }
          await d.mount(t);
          await held.run(() => d.select(t));
          await d.feed(t);
          await d.fixture.advance(t, const Duration(seconds: 8));
          await d.fixture.until(t, () => held.pending.isNotEmpty);
          expect(d.pill?.phase, AutoSyncPillPhase.checking);
          final old = d.fixture.player;
          if (boundary == 'subtitle change') {
            await d.select(t, id: 'replacement-subtitle', seed: 99);
            await d.fixture.until(
              t,
              () => d.pill?.phase == AutoSyncPillPhase.announce,
            );
          } else if (boundary == 'renderer replacement') {
            old.state = old.state.copyWith(position: Duration.zero);
            old.emit('position', Duration.zero);
            await d.fixture.advance(t);
            old.emit('error', 'synthetic MediaCodec video output failure');
            await d.fixture.until(t, () => d.fixture.players.length == 2);
            d.fixture.player.deliverReady();
            await d.fixture.until(
              t,
              () => d.fixture.player.calls.any((c) => c.$1 == 'open'),
            );
            expect(old.disposed.isCompleted, isTrue);
          } else {
            await d.observe(() => t.pumpWidget(const SizedBox()));
            await d.fixture.until(
              t,
              () => d.fixture.player.disposed.isCompleted,
            );
            expect(VideoOutputLease.isHeld, isFalse);
          }
          expect(held.pending, hasLength(1));
          held.release();
          await d.fixture.advance(t);
          expect(
            (old.platform! as FakeNativePlayer).properties['sub-delay'],
            isNull,
          );
          expect(d.native.properties['sub-delay'], isNull);
          expect(d.logs.where((v) => v.contains('Subtitles synced')), isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          await d.close(t);
          if (boundary == 'renderer replacement') VpS2Hooks.install(null);
        }
      },
    );
  }

  for (final boundary in ['subtitle change', 'disposal']) {
    testWidgets(
      'subtitle file filter installation held across $boundary is removed before player teardown',
      (t) async {
        final d = SubtitleSyncDriver(fileTransport: true);
        final gate = Completer<void>();
        await d.initialize(t);
        try {
          await d.mount(t);
          final native = d.native;
          native.heldOperation = (n, v) =>
              n == 'command' && (v as List<String>)[1] == 'add';
          native.beforeOperation = (n, v) =>
              native.heldOperation!(n, v) ? gate.future : null;
          await d.select(t);
          await d.fixture.until(t, () => d.filterCommands.isNotEmpty);
          expect(gate.isCompleted, isFalse);
          expect(d.pill, isNull);
          if (boundary == 'subtitle change') {
            final menu = await openPlayerMenu(t, d.fixture);
            expect(await d.fixture.finish(t, menu.onSubtitlesOff('1')), isTrue);
            menu.onClose();
          } else {
            await d.observe(() => t.pumpWidget(const SizedBox()));
            expect(d.fixture.player.disposed.isCompleted, isFalse);
            expect(VideoOutputLease.isHeld, isTrue);
          }
          expect(gate.isCompleted, isFalse);
          gate.complete();
          await d.fixture.until(
            t,
            () => d.filterCommands.any((c) => c[1] == 'remove'),
          );
          if (boundary == 'disposal') {
            await d.fixture.until(
              t,
              () => d.fixture.player.disposed.isCompleted,
            );
            expect(VideoOutputLease.isHeld, isFalse);
          }
          expect(d.logs.where((v) => v.contains('Trying to sync')), isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await d.close(t);
        }
      },
    );
  }

  testWidgets(
    'subtitle renderer replacement awaits engine filter removal before old player disposal',
    (t) async {
      final d = SubtitleSyncDriver(fileTransport: true);
      final gate = Completer<void>();
      await d.initialize(t);
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      await d.fixture.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      try {
        await d.mount(t);
        await d.select(t);
        await d.installedFile(t);
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.announce,
        );
        final old = d.fixture.player;
        final native = old.platform! as FakeNativePlayer;
        native.heldOperation = (n, v) =>
            n == 'command' && (v as List<String>)[1] == 'remove';
        native.beforeOperation = (n, v) =>
            native.heldOperation!(n, v) ? gate.future : null;
        old.state = old.state.copyWith(position: Duration.zero);
        old.emit('position', Duration.zero);
        await d.fixture.advance(t);
        old.emit('error', 'synthetic MediaCodec video output failure');
        await d.fixture.until(
          t,
          () => native.calls.any(
            (c) => c.$1 == 'command' && (c.$2 as List<String>)[1] == 'remove',
          ),
        );
        expect(old.disposed.isCompleted, isFalse);
        expect(old.calls.where((c) => c.$1 == 'dispose'), isEmpty);
        expect(d.fixture.players, hasLength(1));
        expect(VideoOutputLease.isHeld, isTrue);
        expect(gate.isCompleted, isFalse);
        gate.complete();
        await d.fixture.until(t, () => d.fixture.players.length == 2);
        d.fixture.player.deliverReady();
        await d.fixture.until(
          t,
          () => d.fixture.player.calls.any((c) => c.$1 == 'open'),
        );
        expect(old.disposed.isCompleted, isTrue);
        expect(d.pill, isNull);
        expect(
          d.logs.where((v) => v.contains('controller installed')),
          hasLength(2),
        );
        expect(
          (d.fixture.player.platform as FakeNativePlayer).calls.where(
            (c) => c.$1 == 'command' && (c.$2 as List<String>).first == 'af',
          ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close(t);
        VpS2Hooks.install(null);
      }
    },
  );

  testWidgets(
    'subtitle audio track event restarts announcement and manual offset cancels the ladder',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        t.view.physicalSize = const Size(1280, 1000);
        await d.fixture.advance(t);
        await d.select(t, caption: 'Short caption.');
        await d.feed(t);
        await d.timerEdge(t, const Duration(seconds: 5));
        expect(d.pill, isNull);
        await d.observe(
          () => d.fixture.player.setAudioTrack(
            const mk.AudioTrack('2', 'French', 'fra'),
          ),
        );
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.announce,
        );
        expect(d.logs.where((v) => v.contains('Trying to sync')), hasLength(2));
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        final overlay = t.widget<SubtitleLinePickerOverlay>(
          find.byType(SubtitleLinePickerOverlay),
        );
        await offset(t, d, overlay.onOffsetChanged, 900);
        expect(d.pill, isNull);
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 24));
        expect(
          d.logs.where((v) => v.contains('Checking subtitle timing')),
          isEmpty,
        );
        expect(d.native.properties['sub-delay'], '0.900');
      } finally {
        await d.close(t);
      }
    },
  );

  for (final external in [false, true]) {
    for (final boundary in ['dismissal', 'replacement', 'disposal']) {
      testWidgets(
        'subtitle saved ${external ? 'line picker' : 'stepper'} callback after $boundary keeps original effect order',
        (t) async {
          final d = SubtitleSyncDriver();
          await d.initialize(t);
          try {
            await d.mount(t);
            if (external) {
              await d.select(t);
              await d.feed(t, durationMs: 1000);
              expect(d.pill, isNotNull);
            }
            final menu = await openPlayerMenu(t, d.fixture);
            menu.onClose();
            menu.onSyncRequested!();
            await d.fixture.advance(t);
            final dynamic overlay = external
                ? t.widget<SubtitleLinePickerOverlay>(
                    find.byType(SubtitleLinePickerOverlay),
                  )
                : t.widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay));
            final dynamic callback = overlay.onOffsetChanged;
            overlay.onDismiss();
            await d.fixture.advance(t);
            if (boundary == 'replacement') {
              await d.select(t, id: 'new-subtitle');
              await d.fixture.until(t, () => d.pill != null);
            } else if (boundary == 'disposal') {
              await d.observe(() => t.pumpWidget(const SizedBox()));
              await d.fixture.until(
                t,
                () => d.fixture.player.disposed.isCompleted,
              );
            }
            Object? rejected;
            if (external && boundary == 'disposal') {
              await d.observe(() async {
                try {
                  await callback(777);
                } catch (error) {
                  rejected = error;
                }
              });
              expect(
                rejected.toString(),
                contains('used after being disposed'),
              );
            } else {
              await offset(t, d, callback, 777);
            }
            expect(
              await d.fixture.finish(
                t,
                SubtitleSettingsService.instance.getSyncOffsetMs(),
              ),
              777,
            );
            expect(
              d.native.properties['sub-delay'],
              external && boundary == 'disposal' ? null : '0.777',
            );
            expect(find.byType(SyncStepperOverlay), findsNothing);
            expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
            expect(d.errors, isEmpty);
          } finally {
            await d.close(t);
          }
        },
      );
    }
  }
}
