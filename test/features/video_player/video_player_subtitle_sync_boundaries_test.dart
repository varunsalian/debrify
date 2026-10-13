import 'dart:io';
import 'dart:async';

import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart'
    show CompletionDelivery, CompletionWrites;
import 'support/player_actions.dart';
import 'video_player_subtitle_edges_test.dart' show decoderError;
import 'support/subtitle_sync_driver.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_sync_overlay_test.dart' show offset;

void main() {
  testWidgets(
    'subtitle rollback held through disposal sees the cleared engine before the mounted UI guard',
    (t) async {
      final d = SubtitleSyncDriver();
      final gate = Completer<void>();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t, id: 'dispose-rollback-original');
        await d.feed(t, durationMs: 1000);
        final previous = d.fixture.player.state.track.subtitle.id;
        await d.select(t, id: 'dispose-rollback-rejected');
        await d.feed(t, durationMs: 1000);
        final player = d.fixture.player;
        final count = player.calls.where((c) => c.$1 == 'subtitle').length;
        player.delays['subtitle'] = gate;
        player.emit('log', decoderError);
        await d.fixture.until(
          t,
          () => player.calls.where((c) => c.$1 == 'subtitle').length > count,
        );
        expect(gate.isCompleted, isFalse);
        await d.observe(() => t.pumpWidget(const SizedBox()));
        await d.fixture.until(t, () => player.disposed.isCompleted);
        expect(gate.isCompleted, isFalse);
        player.delays.remove('subtitle');
        gate.complete();
        await d.fixture.until(
          t,
          () => d.logs.contains(
            'SubtitleAutoSync: external subtitle set (controller=MISSING)',
          ),
        );
        await d.fixture.advance(t);
        expect(player.state.track.subtitle.id, previous);
        expect(
          d.logs.lastWhere(
            (v) => v.startsWith('SubtitleAutoSync: external subtitle'),
          ),
          'SubtitleAutoSync: external subtitle set (controller=MISSING)',
        );
        expect(d.errors, isEmpty);
      } finally {
        d.fixture.player.delays.remove('subtitle');
        if (!gate.isCompleted) gate.complete();
        await d.close(t);
      }
    },
  );

  testWidgets(
    'subtitle manual hide keeps a later offset-suppressed selection quiet when its ladder is rearmed',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        '_runAlignment',
        (v) => v is SubtitleAlignResult,
      );
      await d.initialize(t);
      try {
        await d.mount(t);
        final originalMenu = await d.select(t, caption: 'Short caption.');
        await d.feed(t, durationMs: 1000);
        expect(d.pill?.phase, AutoSyncPillPhase.announce);
        final settings = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        originalMenu.onSubtitleStyleChanged!(
          settings.copyWith(syncOffsetMs: 900),
        );
        await d.fixture.advance(t);
        expect(d.pill, isNull);
        final incomingMenu = await held.run(
          () => d.select(t, id: 'offset-suppressed', caption: 'Short caption.'),
        );
        await d.feed(t);
        expect(d.logs.where((v) => v.contains('Trying to sync')), hasLength(1));
        expect(d.pill, isNull);
        incomingMenu.onSubtitleTrackChanged!();
        await d.fixture.advance(t);
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        expect(d.pill, isNull);
        expect(d.native.properties['sub-delay'], '0.000');
        held.release();
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.synced,
        );
        expect(d.native.properties['sub-delay'], '2.121');
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );

  testWidgets(
    'subtitle desktop passthrough preference still uses the raw Android predicate',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      await d.fixture.finish(
        t,
        PlayerSettingsStorage.setAudioPassthroughEnabled(true),
      );
      try {
        await d.mount(t);
        await d.select(t);
        await d.feed(t, durationMs: 1000);
        expect(
          d.logs,
          contains(
            'SubtitleAutoSync: controller installed (passthrough=false)',
          ),
        );
        expect(d.pill?.phase, AutoSyncPillPhase.announce);
        expect(
          d.native.mapObservers.keys,
          contains('af-metadata/debrify_autosync'),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
  testWidgets(
    'subtitle enabled nonnative backend records rejection and stores the external path without an engine',
    (t) async {
      final d = SubtitleSyncDriver(native: false);
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t);
        expect(
          d.logs,
          contains(
            'SubtitleAutoSync: not installing — player backend is not NativePlayer (FakePlatformPlayer)',
          ),
        );
        expect(
          d.logs,
          contains(
            'SubtitleAutoSync: external subtitle set (controller=MISSING)',
          ),
        );
        expect(d.pill, isNull);
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
          d.fixture.player.state.track.subtitle.id,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );

  for (final sessionOffset in [1500, -1500]) {
    testWidgets(
      sessionOffset > 0
          ? 'subtitle cold window remains quiet when a late session offset suppresses listening then a track reset releases the ladder'
          : 'subtitle cold negative session offset is applied by the suspended settings load and suppresses listening',
      (t) async {
        // A callback belonging to the outgoing route changes only the shared
        // session offset. It cannot reset the incoming route's window flag.
        final old = SubtitleSyncDriver();
        await old.initialize(t, enabled: false);
        await old.mount(t);
        final oldMenu = await openPlayerMenu(t, old.fixture);
        oldMenu.onClose();
        oldMenu.onSyncRequested!();
        await old.fixture.advance(t);
        final dynamic callback = t
            .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
            .onOffsetChanged;
        await old.close(t);

        final d = SubtitleSyncDriver();
        final font = CompletionDelivery('loadAll', (v) => v is int);
        final alignment = CompletionDelivery(
          '_runAlignment',
          (v) => v is SubtitleAlignResult,
        );
        await d.initialize(t);
        try {
          await font.run(() => d.mount(t));
          await d.fixture.until(t, () => font.pending.isNotEmpty);
          await offset(t, old, callback, sessionOffset);
          expect(
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.getSyncOffsetMs(),
            ),
            sessionOffset,
          );
          font.release();
          await d.fixture.until(
            t,
            () =>
                d.native.properties['sub-delay'] ==
                (sessionOffset / 1000).toStringAsFixed(3),
          );
          final menu = await alignment.run(() => d.select(t));
          await d.feed(t);
          expect(d.logs.where((v) => v.contains('Trying to sync')), isEmpty);
          expect(
            d.logs.join('\n'),
            contains('listening suppressed — stored offset ${sessionOffset}ms'),
          );
          expect(d.pill, isNull);
          // This is the panel's callback after its accepted track-change Future.
          // A slow preference write can place it after engine activation.
          menu.onSubtitleTrackChanged!();
          await d.fixture.advance(t);
          expect(d.native.properties['sub-delay'], '0.000');
          await d.fixture.advance(t, const Duration(seconds: 8));
          await d.fixture.until(t, () => alignment.pending.isNotEmpty);
          expect(d.pill, isNull);
          alignment.release();
          await d.fixture.until(
            t,
            () => d.pill?.phase == AutoSyncPillPhase.synced,
          );
          expect(d.native.properties['sub-delay'], '1.869');
          expect(d.errors, isEmpty);
          expect(old.errors, isEmpty);
        } finally {
          font.release();
          alignment.release();
          await d.close(t);
        }
      },
    );
  }
  for (final enabled in [false, true]) {
    testWidgets(
      'subtitle stored enablement $enabled gates actual installation and selection',
      (t) async {
        final d = SubtitleSyncDriver();
        await d.initialize(t, enabled: enabled);
        try {
          await d.mount(t);
          await d.select(t);
          expect(
            d.logs,
            contains('SubtitleAutoSync: pref loaded, enabled=$enabled'),
          );
          if (enabled) {
            await d.feed(t, durationMs: 1000);
            expect(d.pill?.phase, AutoSyncPillPhase.announce);
            expect(
              d.logs,
              contains(
                'SubtitleAutoSync: controller installed (passthrough=false)',
              ),
            );
            expect(
              d.logs,
              contains(
                'SubtitleAutoSync: external subtitle set (controller=present)',
              ),
            );
          } else {
            expect(d.filterCommands, isEmpty);
            expect(d.pill, isNull);
            expect(
              d.logs,
              contains(
                'SubtitleAutoSync: not installing — enabled=false web=false platform=${Platform.operatingSystem}',
              ),
            );
            expect(
              d.logs,
              contains(
                'SubtitleAutoSync: external subtitle set (controller=MISSING)',
              ),
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close(t);
        }
      },
    );
  }

  testWidgets(
    'subtitle native manual property rejection escapes while session and UI still update',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        d.native.beforeOperation = (n, v) {
          if (n == 'setProperty' && (v as (String, String)).$1 == 'sub-delay') {
            throw StateError('manual-native-rejection');
          }
        };
        final overlay = t.widget<SyncStepperOverlay>(
          find.byType(SyncStepperOverlay),
        );
        await offset(t, d, overlay.onOffsetChanged, -2500);
        await d.fixture.until(t, () => d.errors.isNotEmpty);
        expect(
          d.errors.single.toString(),
          'Bad state: manual-native-rejection',
        );
        expect(d.native.properties['sub-delay'], isNull);
        expect(
          t
              .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
              .offsetMs,
          -2500,
        );
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          -2500,
        );
        expect(
          d.logs.where((v) => v.contains('offset persistence failed')),
          isEmpty,
        );
      } finally {
        await d.close(t);
      }
    },
  );

  testWidgets(
    'subtitle native auto property rejection escapes the persistence catch and still reports synced',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t);
        await d.feed(t);
        final previous = d.native.beforeOperation;
        d.native.beforeOperation = (n, v) {
          if (n == 'setProperty' && (v as (String, String)).$1 == 'sub-delay') {
            throw StateError('auto-native-rejection');
          }
          return previous?.call(n, v);
        };
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.synced,
        );
        expect(d.errors.single.toString(), 'Bad state: auto-native-rejection');
        expect(d.native.properties['sub-delay'], isNull);
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          1869,
        );
        expect(
          d.logs.where((v) => v.contains('offset persistence failed')),
          isEmpty,
        );
      } finally {
        await d.close(t);
      }
    },
  );

  for (final verdict in [false, true]) {
    testWidgets(
      'subtitle dispose cancels ${verdict ? 'result hold' : 'announcement'} before notifier disposal',
      (t) async {
        final d = SubtitleSyncDriver();
        await d.initialize(t);
        try {
          await d.mount(t);
          await d.select(t);
          await d.feed(t, durationMs: verdict ? 180000 : 1000);
          if (verdict) {
            await d.fixture.advance(t, const Duration(seconds: 8));
            await d.fixture.until(
              t,
              () => d.pill?.phase == AutoSyncPillPhase.synced,
            );
          } else {
            expect(d.pill?.phase, AutoSyncPillPhase.announce);
          }
          await d.observe(() => t.pumpWidget(const SizedBox()));
          await d.fixture.until(t, () => d.fixture.player.disposed.isCompleted);
          await d.fixture.advance(t, const Duration(seconds: 6));
          expect(d.errors, isEmpty);
          expect(d.native.mapObservers, isEmpty);
          expect(d.filterCommands.last, ['af', 'remove', '@debrify_autosync']);
        } finally {
          await d.close(t);
        }
      },
    );
  }

  testWidgets(
    'subtitle engine offset before settings delivery keeps null UI model and accepts the old snapshot later',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        'loadSubtitleSettings',
        (v) => v is SubtitleSettingsData,
      );
      await d.initialize(t);
      try {
        await held.run(() => d.mount(t));
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        await d.select(t);
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.synced,
        );
        expect(d.native.properties['sub-delay'], '1.869');
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          1869,
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
              .currentOffsetMs,
          0,
        );
        expect((held.values.single as SubtitleSettingsData).syncOffsetMs, 0);
        held.release();
        await d.fixture.advance(t);
        expect(
          t
              .widget<SubtitleLinePickerOverlay>(
                find.byType(SubtitleLinePickerOverlay),
              )
              .currentOffsetMs,
          0,
        );
        expect(d.native.properties['sub-delay'], '1.869');
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );

  testWidgets(
    'subtitle suspended prefs initialization can overwrite incoming cache with a stale profile wrapper',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        'SubtitleSettingsService._ensurePrefs',
        (v) => v is ProfilePreferences,
      );
      await d.initialize(t, enabled: false);
      final outgoing = ProfileRuntime.capture();
      final prefs = await d.fixture.finish(t, ProfilePreferences.instance());
      await d.fixture.finish(t, prefs.setInt('subtitle_color_index', 1));
      try {
        await held.run(() => d.mount(t));
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        await incomingProfile(t, d.fixture);
        final incoming = ProfileRuntime.capture();
        await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.setColorIndex(4),
        );
        final settings = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        expect(settings.colorIndex, 4);
        held.release();
        await d.fixture.until(t, () => d.errors.isNotEmpty);
        expect(
          d.errors.single.toString(),
          contains('stale ProfilePreferences'),
        );
        final physical = await t.runAsync(CompletionWrites.install);
        expect(await physical!.physical(outgoing, 'subtitle_color_index'), 1);
        expect(await physical.physical(incoming, 'subtitle_color_index'), 4);
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );
}
