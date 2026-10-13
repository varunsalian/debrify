import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/local_completion_driver.dart'
    show CompletionDelivery, CompletionWrites;
import 'support/player_actions.dart';
import 'support/subtitle_sync_driver.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_sync_overlay_test.dart' show offset;

void main() {
  testWidgets(
    'subtitle overlapping route resets singleton offset while the outgoing route retains its model',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t, enabled: false);
      try {
        await d.mount(t);
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        final overlay = t.widget<SyncStepperOverlay>(
          find.byType(SyncStepperOverlay),
        );
        await offset(t, d, overlay.onOffsetChanged, 500);
        overlay.onDismiss();
        await d.fixture.advance(t);
        final route = d.fixture.actions.start<void>(
          'overlapping subtitle route',
          () => d.fixture.navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const VideoPlayerScreen(
                videoUrl: 'https://player.test/overlap.mp4',
                title: 'Incoming subtitle route',
              ),
            ),
          ),
          held: true,
        );
        await d.fixture.advance(t, const Duration(milliseconds: 300));
        expect(route.isCompleted, isFalse);
        expect(d.fixture.players, hasLength(1));
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          0,
        );
        expect(d.native.properties['sub-delay'], '0.500');
        d.fixture.navigator.currentState!.pop();
        await d.fixture.finish(t, route.future);
        await d.fixture.advance(t, const Duration(milliseconds: 300));
        final returned = await openPlayerMenu(t, d.fixture);
        returned.onClose();
        returned.onSyncRequested!();
        await d.fixture.advance(t);
        expect(
          t
              .widget<SyncStepperOverlay>(find.byType(SyncStepperOverlay))
              .offsetMs,
          500,
        );
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          0,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
  testWidgets(
    'subtitle timing is session only while appearance migrates and persists',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t, enabled: false);
      final scope = ProfileRuntime.capture();
      final prefs = await d.fixture.finish(t, ProfilePreferences.instance());
      await d.fixture.finish(t, prefs.setInt('subtitle_elevation_index', 0));
      final writes = await t.runAsync(CompletionWrites.install);
      try {
        await d.mount(t);
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getElevationIndex(),
          ),
          5,
        );
        expect(
          await writes!.physical(
            scope,
            'subtitle_extreme_bottom_default_adopted_v1',
          ),
          true,
        );
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        final overlay = t.widget<SyncStepperOverlay>(
          find.byType(SyncStepperOverlay),
        );
        await offset(t, d, overlay.onOffsetChanged, 1234);
        expect(
          writes.writes.where((w) => w.$1.contains('sync_offset')),
          isEmpty,
        );
        expect(d.native.properties['sub-delay'], '1.234');
        await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.setColorIndex(1),
        );
        await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.setElevationIndex(3),
        );
        final settings = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        menu.onSubtitleStyleChanged!(settings);
        await d.fixture.advance(t);
        expect(await writes.physical(scope, 'subtitle_color_index'), 1);
        expect(await writes.physical(scope, 'subtitle_elevation_index'), 3);
        final video = t.widget<mkv.Video>(find.byType(mkv.Video));
        expect(
          video.subtitleViewConfiguration.style.color,
          const Color(0xFFFFFF00),
        );
        expect(video.subtitleViewConfiguration.padding.bottom, 180);
        menu.onSubtitleTrackChanged!();
        await d.fixture.advance(t);
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          0,
        );
        expect(d.native.properties['sub-delay'], '0.000');
        expect(
          writes.writes.where((w) => w.$1.contains('sync_offset')),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );

  for (final retire in [false, true]) {
    testWidgets(
      'subtitle already returned snapshot ${retire ? 'after disposal is rejected' : 'after profile handoff is accepted by mounted only'}',
      (t) async {
        final d = SubtitleSyncDriver();
        final held = CompletionDelivery(
          'loadSubtitleSettings',
          (v) => v is SubtitleSettingsData,
        );
        await d.initialize(t, enabled: false);
        final outgoing = ProfileRuntime.capture();
        final prefs = await d.fixture.finish(t, ProfilePreferences.instance());
        await d.fixture.finish(t, prefs.setInt('subtitle_color_index', 1));
        try {
          await held.run(() => d.mount(t));
          await d.fixture.until(t, () => held.pending.isNotEmpty);
          expect((held.values.single as SubtitleSettingsData).colorIndex, 1);
          expect(
            t
                .widget<mkv.Video>(find.byType(mkv.Video))
                .subtitleViewConfiguration
                .style
                .color,
            Colors.white,
          );
          if (retire) {
            await d.observe(() => t.pumpWidget(const SizedBox()));
            await d.fixture.until(
              t,
              () => d.fixture.player.disposed.isCompleted,
            );
          } else {
            await incomingProfile(t, d.fixture);
            final incoming = ProfileRuntime.capture();
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.setColorIndex(4),
            );
            final physical = await t.runAsync(() => CompletionWrites.install());
            expect(
              await physical!.physical(outgoing, 'subtitle_color_index'),
              1,
            );
            expect(
              await physical.physical(incoming, 'subtitle_color_index'),
              4,
            );
          }
          expect(held.pending, hasLength(1));
          held.release();
          await d.fixture.advance(t);
          if (!retire) {
            expect(
              t
                  .widget<mkv.Video>(find.byType(mkv.Video))
                  .subtitleViewConfiguration
                  .style
                  .color,
              const Color(0xFFFFFF00),
            );
            expect(
              await d.fixture.finish(
                t,
                SubtitleSettingsService.instance.getColorIndex(),
              ),
              4,
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          await d.close(t);
        }
      },
    );
  }

  for (final incomingLoad in [false, true]) {
    testWidgets(
      'subtitle pending font lookup after shared prefs reset ${incomingLoad ? 'reads incoming prefs and font' : 'propagates null prefs error'}',
      (t) async {
        final d = SubtitleSyncDriver();
        final held = CompletionDelivery('loadAll', (v) => v is int);
        await d.initialize(t, enabled: false);
        final outgoing = ProfileRuntime.capture();
        final prefs = await d.fixture.finish(t, ProfilePreferences.instance());
        await d.fixture.finish(t, prefs.setInt('subtitle_color_index', 1));
        try {
          await held.run(() => d.mount(t));
          await d.fixture.until(t, () => held.pending.isNotEmpty);
          expect(held.values.single, 0);
          await incomingProfile(t, d.fixture);
          final incoming = ProfileRuntime.capture();
          if (incomingLoad) {
            await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.setColorIndex(4),
            );
            await d.fixture.finish(
              t,
              SubtitleFontService.instance.setSelectedFontId('roboto'),
            );
            final current = await d.fixture.finish(
              t,
              SubtitleSettingsService.instance.loadAll(),
            );
            expect(current.colorIndex, 4);
            expect(current.fontIndex, 1);
            expect(current.fontFamily, 'Roboto');
          }
          expect(held.pending, hasLength(1));
          held.release();
          await d.fixture.advance(t);
          if (incomingLoad) {
            await d.fixture.until(
              t,
              () =>
                  t
                      .widget<mkv.Video>(find.byType(mkv.Video))
                      .subtitleViewConfiguration
                      .style
                      .color ==
                  const Color(0xFFFF00FF),
            );
            final video = t.widget<mkv.Video>(find.byType(mkv.Video));
            expect(video.subtitleViewConfiguration.style.fontFamily, 'Roboto');
            expect(d.errors, isEmpty);
          } else {
            await d.fixture.until(t, () => d.errors.isNotEmpty);
            expect(d.errors.single.toString(), contains('Null check operator'));
            expect(
              t
                  .widget<mkv.Video>(find.byType(mkv.Video))
                  .subtitleViewConfiguration
                  .style
                  .color,
              Colors.white,
            );
          }
          final physical = await t.runAsync(CompletionWrites.install);
          expect(await physical!.physical(outgoing, 'subtitle_color_index'), 1);
          expect(
            await physical.physical(incoming, 'subtitle_color_index'),
            incomingLoad ? 4 : null,
          );
        } finally {
          held.release();
          await d.close(t);
        }
      },
    );
  }

  testWidgets(
    'subtitle style callback saved before disposal skips all later effects',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        final menu = await openPlayerMenu(t, d.fixture);
        final settings = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        await d.observe(() => t.pumpWidget(const SizedBox()));
        await d.fixture.until(t, () => d.fixture.player.disposed.isCompleted);
        final nativeWrites = d.native.calls
            .where((c) => c.$1 == 'setProperty')
            .length;
        Object? rejected;
        try {
          menu.onSubtitleStyleChanged!(
            settings.copyWith(syncOffsetMs: 1234, colorIndex: 1),
          );
        } catch (error) {
          rejected = error;
        }
        expect(
          rejected,
          isNull,
          reason:
              'Disposed style callback stops before setState or native effects',
        );
        await d.fixture.advance(t);
        expect(
          d.native.calls.where((c) => c.$1 == 'setProperty'),
          hasLength(nativeWrites),
        );
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          0,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
}
