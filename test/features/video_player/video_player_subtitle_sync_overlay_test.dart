import 'package:debrify/services/profiles/tvos_profile_recovery_store.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show FocusManager, AnimatedOpacity;
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/player_actions.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/subtitle_sync_driver.dart';

Future<void> offset(
  WidgetTester t,
  SubtitleSyncDriver d,
  dynamic cb,
  int ms,
) async {
  final dynamic pending = d.observe<dynamic>(() => cb(ms));
  if (pending is Future) await d.fixture.finish<dynamic>(t, pending);
  await d.fixture.advance(t);
}

void main() {
  for (final external in [false, true]) {
    testWidgets(
      'subtitle saved ${external ? 'line' : 'stepper'} manual callback cancels a held real alignment and hides checking',
      (t) async {
        final d = SubtitleSyncDriver();
        final held = CompletionDelivery(
          '_runAlignment',
          (v) => v is SubtitleAlignResult,
        );
        await d.initialize(t);
        try {
          await d.mount(t);
          dynamic callback;
          if (!external) {
            final menu = await openPlayerMenu(t, d.fixture);
            menu.onClose();
            menu.onSyncRequested!();
            await d.fixture.advance(t);
            final overlay = t.widget<SyncStepperOverlay>(
              find.byType(SyncStepperOverlay),
            );
            callback = overlay.onOffsetChanged;
            overlay.onDismiss();
            await d.fixture.advance(t);
          }
          await held.run(() => d.select(t, caption: 'Short caption.'));
          await d.feed(t);
          await d.fixture.advance(t, const Duration(seconds: 8));
          await d.fixture.until(t, () => held.pending.isNotEmpty);
          expect(d.pill?.phase, AutoSyncPillPhase.checking);
          if (external) {
            final menu = await openPlayerMenu(t, d.fixture);
            menu.onClose();
            menu.onSyncRequested!();
            await d.fixture.advance(t);
            final overlay = t.widget<SubtitleLinePickerOverlay>(
              find.byType(SubtitleLinePickerOverlay),
            );
            callback = overlay.onOffsetChanged;
            overlay.onDismiss();
            await d.fixture.advance(t);
          }
          await offset(t, d, callback, 900);
          expect(d.pill, isNull);
          expect(d.native.properties['sub-delay'], '0.900');
          expect(held.pending, hasLength(1));
          held.release();
          await d.fixture.advance(t);
          expect(d.native.properties['sub-delay'], '0.900');
          expect(
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.getSyncOffsetMs(),
            ),
            900,
          );
          expect(d.logs.where((v) => v.contains('Subtitles synced')), isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          await d.close(t);
        }
      },
    );
  }
  testWidgets(
    'subtitle early stepper reads zero while the original settings snapshot is suspended',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        'loadSubtitleSettings',
        (v) => v is SubtitleSettingsData,
      );
      await d.initialize(t, enabled: false);
      try {
        await held.run(() => d.mount(t));
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        expect(find.byType(SyncStepperOverlay), findsOneWidget);
        expect(
          t
              .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
              .offsetMs,
          0,
        );
        expect(held.pending, hasLength(1));
        held.release();
        await d.fixture.advance(t);
        expect(
          t
              .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
              .offsetMs,
          0,
        );
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );

  testWidgets(
    'subtitle route Back dismisses the top sync overlay before leaving playback',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      PlatformUtil.debugSetAndroidTvCached(true);
      try {
        await d.mount(t);
        t.widget<TvControls>(find.byType(TvControls)).onShowTracks();
        await d.fixture.advance(t, const Duration(milliseconds: 300));
        final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        expect(find.byType(SyncStepperOverlay), findsOneWidget);
        await d.fixture.finish(t, d.fixture.navigator.currentState!.maybePop());
        await d.fixture.advance(t);
        expect(find.byType(SyncStepperOverlay), findsNothing);
        expect(d.fixture.player.disposed.isCompleted, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
  testWidgets(
    'subtitle TV line picker receives the first Select through the focus release',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      PlatformUtil.debugSetAndroidTvCached(true);
      try {
        await d.mount(t);
        await d.select(t, caption: 'Short caption.');
        t.widget<TvControls>(find.byType(TvControls)).onShowTracks();
        await d.fixture.advance(t, const Duration(milliseconds: 300));
        final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        await d.fixture.until(
          t,
          () => find.text('Stepper').evaluate().isNotEmpty,
        );
        final element = t.element(find.byType(SubtitleLinePickerOverlay));
        await d.fixture.key(t, LogicalKeyboardKey.enter);
        expect(find.text('Hide stepper'), findsOneWidget);
        expect(
          identical(element, t.element(find.byType(SubtitleLinePickerOverlay))),
          isTrue,
        );
        await d.fixture.key(t, LogicalKeyboardKey.escape);
        expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
  for (final external in [false, true]) {
    testWidgets(
      'subtitle ${external ? 'line picker' : 'stepper'} updates session and native delay and dismisses',
      (t) async {
        final d = SubtitleSyncDriver();
        await d.initialize(t);
        try {
          await d.mount(t);
          if (external) await d.select(t);
          final menu = await openPlayerMenu(t, d.fixture);
          menu.onClose();
          await d.fixture.advance(t);
          final controlsOpacity = find
              .ancestor(
                of: find.byType(Controls),
                matching: find.byType(AnimatedOpacity),
              )
              .first;
          expect(t.widget<AnimatedOpacity>(controlsOpacity).opacity, 0);
          await t.tapAt(t.getCenter(find.byType(mkv.Video)));
          await d.fixture.advance(t, const Duration(milliseconds: 300));
          expect(t.widget<AnimatedOpacity>(controlsOpacity).opacity, 1);
          menu.onSyncRequested!();
          await d.fixture.advance(t);
          expect(
            t
                .widget<AnimatedOpacity>(
                  find
                      .ancestor(
                        of: find.byType(Controls),
                        matching: find.byType(AnimatedOpacity),
                      )
                      .first,
                )
                .opacity,
            0,
            reason: 'Opening sync hides the transport controls',
          );
          if (external) {
            await d.fixture.until(
              t,
              () =>
                  find.byType(SubtitleLinePickerOverlay).evaluate().isNotEmpty,
            );
            final overlay = t.widget<SubtitleLinePickerOverlay>(
              find.byType(SubtitleLinePickerOverlay),
            );
            expect(
              overlay.subtitleFilePath,
              d.fixture.player.state.track.subtitle.id,
            );
            expect(overlay.currentOffsetMs, 0);
            d.fixture.player.state = d.fixture.player.state.copyWith(
              position: const Duration(seconds: 9),
            );
            expect(overlay.getCurrentPositionMs(), 9000);
            await offset(t, d, overlay.onOffsetChanged, -1234);
            expect(
              t
                  .widget<SubtitleLinePickerOverlay>(
                    find.byType(SubtitleLinePickerOverlay),
                  )
                  .currentOffsetMs,
              -1234,
            );
            overlay.onDismiss();
          } else {
            final overlay = t.widget<SyncStepperOverlay>(
              find.byType(SyncStepperOverlay),
            );
            expect(overlay.offsetMs, 0);
            await offset(t, d, overlay.onOffsetChanged, -1234);
            expect(
              t
                  .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
                  .offsetMs,
              -1234,
            );
            overlay.onDismiss();
          }
          await d.fixture.advance(t);
          expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
          expect(find.byType(SyncStepperOverlay), findsNothing);
          expect(d.native.properties['sub-delay'], '-1.234');
          expect(
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.getSyncOffsetMs(),
            ),
            -1234,
          );
          expect(d.pill, isNull);
          expect(d.errors, isEmpty);
        } finally {
          await d.close(t);
        }
      },
    );
  }

  for (final ms in [-4000000, 4000000]) {
    testWidgets(
      'subtitle stepper clamps callback $ms before native and rendered writes',
      (t) async {
        final d = SubtitleSyncDriver();
        await d.initialize(t);
        try {
          await d.mount(t);
          final menu = await openPlayerMenu(t, d.fixture);
          menu.onClose();
          menu.onSyncRequested!();
          await d.fixture.advance(t);
          final overlay = t.widget<SyncStepperOverlay>(
            find.byType(SyncStepperOverlay),
          );
          await offset(t, d, overlay.onOffsetChanged, ms);
          final clamped = ms.sign * 3600000;
          expect(
            t
                .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
                .offsetMs,
            clamped,
          );
          expect(d.native.properties['sub-delay'], '${clamped / 1000}00');
          expect(
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.getSyncOffsetMs(),
            ),
            clamped,
          );
        } finally {
          await d.close(t);
        }
      },
    );
  }

  testWidgets(
    'subtitle style callback renders appearance without restarting unchanged timing',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t);
        await d.fixture.until(t, () => d.native.mapObservers.isNotEmpty);
        final menu = await openPlayerMenu(t, d.fixture);
        final settings = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        final commands = d.filterCommands.length;
        menu.onSubtitleStyleChanged!(
          settings.copyWith(
            sizeIndex: 4,
            colorIndex: 1,
            elevationIndex: 3,
            bold: true,
          ),
        );
        await d.fixture.advance(t);
        final video = t.widget<mkv.Video>(find.byType(mkv.Video));
        expect(video.subtitleViewConfiguration.style.fontSize, 64);
        expect(
          video.subtitleViewConfiguration.style.color,
          const Color(0xFFFFFF00),
        );
        expect(
          video.subtitleViewConfiguration.style.fontWeight,
          FontWeight.bold,
        );
        expect(video.subtitleViewConfiguration.padding.bottom, 180);
        expect(d.filterCommands, hasLength(commands));
        expect(d.native.properties['sub-delay'], isNull);
        expect(d.pill, isNotNull);
        menu.onSubtitleStyleChanged!(settings.copyWith(syncOffsetMs: 1234));
        await d.fixture.advance(t);
        expect(d.pill, isNull);
        expect(d.native.properties['sub-delay'], '1.234');
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 24));
        expect(d.native.properties['sub-delay'], '1.234');
        expect(
          d.logs.where((line) => line.contains('Checking subtitle timing')),
          isEmpty,
        );
      } finally {
        await d.close(t);
      }
    },
  );

  for (final native in [false, true]) {
    testWidgets(
      'subtitle timing reset clears session and ${native ? 'native property' : 'skips nonnative property'}',
      (t) async {
        final d = SubtitleSyncDriver(native: native);
        await d.initialize(t);
        try {
          await d.mount(t);
          final menu = await openPlayerMenu(t, d.fixture);
          final settings = await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.loadAll(),
          );
          menu.onSubtitleStyleChanged!(settings.copyWith(syncOffsetMs: 700));
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.setSyncOffsetMs(700),
          );
          menu.onSubtitleTrackChanged!();
          await d.fixture.advance(t);
          expect(
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.getSyncOffsetMs(),
            ),
            0,
          );
          if (native) expect(d.native.properties['sub-delay'], '0.000');
          menu.onClose();
          menu.onSyncRequested!();
          await d.fixture.advance(t);
          expect(
            t
                .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
                .offsetMs,
            0,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close(t);
        }
      },
    );
  }

  for (final tvos in [false, true]) {
    testWidgets(
      'subtitle TV ${tvos ? 'tvOS' : 'Android TV'} first key repeat and Back retain overlay element',
      (t) async {
        final d = SubtitleSyncDriver(native: false);
        await d.initialize(t);
        final checkpoint = TvOsProfileRecoveryStore.checkpointCallback;
        TvOsProfileRecoveryStore.checkpointCallback = () async {};
        PlatformUtil.debugSetAndroidTvCached(!tvos);
        PlatformUtil.debugSetTvOS(tvos);
        try {
          await d.mount(t);
          // A public keyboard action opens the player's menu on television.
          await d.fixture.key(t, LogicalKeyboardKey.keyS);
          // Use the current menu callback, preserving the real focus handoff.
          final controls = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'TvControls',
          );
          final dynamic bar = t.widget(controls);
          bar.onShowTracks();
          await d.fixture.advance(t, const Duration(milliseconds: 300));
          final menuFinder = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'PlayerMenuPanel',
          );
          final dynamic menu = t.widget(menuFinder);
          menu.onClose();
          menu.onSyncRequested();
          await d.fixture.advance(t);
          await d.fixture.until(
            t,
            () =>
                FocusManager.instance.primaryFocus?.debugLabel ==
                'sync-stepper-overlay',
          );
          final element = t.element(find.byType(SyncStepperOverlay));
          await d.fixture.key(t, LogicalKeyboardKey.arrowRight);
          expect(
            t
                .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
                .offsetMs,
            100,
          );
          await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          for (var i = 0; i < 8; i++) {
            await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
            await d.fixture.advance(t);
          }
          await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
          expect(
            t
                .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
                .offsetMs,
            1300,
          );
          expect(
            identical(element, t.element(find.byType(SyncStepperOverlay))),
            isTrue,
          );
          await d.fixture.key(t, LogicalKeyboardKey.enter);
          expect(
            t
                .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
                .offsetMs,
            0,
          );
          await d.fixture.key(t, LogicalKeyboardKey.escape);
          expect(find.byType(SyncStepperOverlay), findsNothing);
          expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
          expect(d.errors, isEmpty);
        } finally {
          await d.close(t);
          TvOsProfileRecoveryStore.checkpointCallback = checkpoint;
        }
      },
    );
  }
}
