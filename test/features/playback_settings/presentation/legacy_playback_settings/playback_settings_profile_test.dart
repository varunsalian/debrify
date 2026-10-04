import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/settings/external_player_settings_page.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playback_settings_fixture.dart';
import '../../../../support/playback_settings_profiles.dart';

void main() {
  playbackHarness();
  setUp(() => AppThemeAdapter.debugUseTestTypography = true);
  tearDown(() => AppThemeAdapter.debugUseTestTypography = false);
  testWidgets('active-profile setter and device font list remain separate', (
    tester,
  ) async {
    await playbackCase(tester, (f) async {
      final p = PlaybackProfiles();
      await tester.runAsync(() => p.open(f.directory));

      try {
        await f.mount(tester, section: PlaybackSettingsSection.subtitles);

        playbackPreferences.writes.clear();
        await tester.runAsync(
          () async => await f.member('setSubtitleBold')(true),
        );

        expect(playbackPreferences.writes, [
          (p.a.preferenceKey('subtitle_bold'), true),
        ]);
        expect(
          playbackRawPreferences.get(p.b.preferenceKey('subtitle_bold')),
          isNull,
        );
        final fontFile = await tester.runAsync(
          () => File(
            'assets/fonts/Roboto-Regular.ttf',
          ).copy('${f.directory.path}/Shared.ttf'),
        );

        f.picker.result = FilePickerResult([
          PlatformFile(name: 'Shared.ttf', path: fontFile!.path, size: 1),
        ]);
        await tester.runAsync(() async => await f.member('importCustomFont')());

        final font = ((await tester.runAsync(
          SubtitleFontService.instance.getCustomFonts,
        ))!).single;
        expect(
          playbackRawPreferences.getString(
            p.a.preferenceKey('subtitle_selected_font_id'),
          ),
          font.id,
        );

        expect(
          jsonDecode(
            playbackRawPreferences.getString('subtitle_custom_fonts')!,
          ),
          hasLength(1),
        );

        await tester.pumpWidget(const SizedBox.shrink());

        await tester.runAsync(p.publishB);

        SubtitleFontService.instance.resetProfileScope();
        SubtitleSettingsService.instance.resetProfileScope();
        expect(
          ((await tester.runAsync(
            SubtitleFontService.instance.getCustomFonts,
          ))!).single.id,
          font.id,
        );
        expect(
          await tester.runAsync(SubtitleFontService.instance.getSelectedFontId),
          'default',
        );
        expect(
          playbackRawPreferences.get(
            p.b.preferenceKey('subtitle_selected_font_id'),
          ),
          isNull,
        );
        await tester.runAsync(
          () => SubtitleFontService.instance.removeCustomFont(font.id),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());

        await tester.runAsync(p.close);
      }
    });
  });
  testWidgets(
    'idle pushed route is popped by picker and incoming page owns its keys',
    (tester) async {
      await playbackCase(tester, (f) async {
        final p = PlaybackProfiles();
        await tester.runAsync(() => p.open(f.directory));

        try {
          await tester.runAsync(
            () => ProfileGateStyle.set(ProfileGateStyle.classic),
          );
          await playbackSeed({
            p.a.preferenceKey('player_default_aspect_index'): 3,
            p.b.preferenceKey('player_default_aspect_index'): 1,
          });
          await f.mount(
            tester,
            home: ProfileGate(
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => pushSettingsPage(
                      context,
                      ExternalPlayerSettingsPage(
                        key: f.key,
                        section: PlaybackSettingsSection.video,
                      ),
                    ),
                    child: const Text('Open playback'),
                  ),
                ),
              ),
            ),
          );
          await f.until(tester, () => find.text('A').evaluate().isNotEmpty);

          await tester.runAsync(() async {
            MainPageBridge.switchProfile!(p.a.profileId);
          });
          await f.until(
            tester,
            () => find.text('Open playback').evaluate().isNotEmpty,
          );

          await tester.tap(find.text('Open playback'));
          await f.loaded(tester);
          expect(f.member('defaultAspectIndex'), 3);
          final old = f.key.currentState!;
          final aBefore = {
            for (final k in playbackRawPreferences.getKeys().where(
              (k) => k.startsWith(p.a.preferencePrefix),
            ))
              k: playbackRawPreferences.get(k),
          };

          expect(
            playbackPreferences.writes
                .where((w) => w.$1.startsWith(p.a.preferencePrefix))
                .toList(),
            [
              (
                p.a.preferenceKey('android_video_renderer_mode'),
                'direct_mediacodec',
              ),
              (
                p.a.preferenceKey('android_video_renderer_gpu_migration_v1'),
                true,
              ),
              (
                p.a.preferenceKey('subtitle_extreme_bottom_default_adopted_v1'),
                true,
              ),
            ],
          );
          playbackPreferences.writes.clear();

          await tester.runAsync(() async {
            MainPageBridge.switchProfile!(p.b.profileId);
          });
          await f.until(
            tester,
            () =>
                ProfileRuntime.capture().profileId == p.b.profileId &&
                find.text('Open playback').evaluate().isNotEmpty,
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(old.mounted, isFalse);
          expect(find.byType(ExternalPlayerSettingsPage), findsNothing);
          expect(f.navigator.currentState!.canPop(), isFalse);
          expect(
            playbackPreferences.writes.where(
              (w) => w.$1.startsWith(p.a.preferencePrefix),
            ),
            isEmpty,
          );

          playbackPreferences.writes.clear();

          await tester.tap(find.text('Open playback'));
          await f.loaded(tester);
          expect(f.key.currentState, isNot(same(old)));
          expect(f.member('defaultAspectIndex'), 1);
          expect(playbackPreferences.writes, [
            (
              p.b.preferenceKey('android_video_renderer_mode'),
              'direct_mediacodec',
            ),
            (
              p.b.preferenceKey('android_video_renderer_gpu_migration_v1'),
              true,
            ),
            (
              p.b.preferenceKey('subtitle_extreme_bottom_default_adopted_v1'),
              true,
            ),
          ]);
          expect({
            for (final k in playbackRawPreferences.getKeys().where(
              (k) => k.startsWith(p.a.preferencePrefix),
            ))
              k: playbackRawPreferences.get(k),
          }, aBefore);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());

          await tester.runAsync(p.close);
        }
      });
    },
  );
  testWidgets(
    'held issued renderer write lands in A and following write rejects stale session',
    (tester) async {
      await playbackCase(tester, (f) async {
        final p = PlaybackProfiles();
        await tester.runAsync(() => p.open(f.directory));

        final held = Completer<void>();
        try {
          await f.mount(tester, section: PlaybackSettingsSection.video);

          playbackPreferences.writes.clear();
          playbackPreferences.holdWrite = held;
          final action =
              f.member('setAndroidVideoRendererMode')(
                    AndroidVideoRendererMode.automatic.storageKey,
                  )
                  as Future<void>;
          final outcome = action.then<Object?>(
            (_) => null,
            onError: (Object e) => e,
          );
          await f.until(tester, () => playbackPreferences.writes.isNotEmpty);

          await tester.pumpWidget(const SizedBox.shrink());

          await tester.runAsync(p.publishB);

          held.complete();
          playbackPreferences.holdWrite = null;
          final error = await tester.runAsync(() => outcome);
          expect(error, isA<StateError>());
          expect(error.toString(), contains('stale ProfilePreferences'));
          expect(playbackPreferences.writes, [
            (p.a.preferenceKey('android_video_renderer_mode'), 'automatic'),
          ]);
          expect(
            playbackRawPreferences.get(
              p.a.preferenceKey('android_video_renderer_mode'),
            ),
            'automatic',
          );
          expect(
            playbackRawPreferences.get(
              p.b.preferenceKey('android_video_renderer_mode'),
            ),
            isNull,
          );
        } finally {
          if (!held.isCompleted) held.complete();
          playbackPreferences.holdWrite = null;

          await tester.pumpWidget(const SizedBox.shrink());

          await tester.runAsync(p.close);
        }
      });
    },
  );
  testWidgets(
    'pending font picker resumes device import and selection in incoming profile after pop',
    (tester) async {
      await playbackCase(tester, (f) async {
        final p = PlaybackProfiles();
        await tester.runAsync(() => p.open(f.directory));

        try {
          await f.mount(tester, section: PlaybackSettingsSection.subtitles);
          final source = await tester.runAsync(
            () => File(
              'assets/fonts/Roboto-Regular.ttf',
            ).copy('${f.directory.path}/Late.ttf'),
          );
          final picker = Completer<FilePickerResult?>();
          f.picker.pending = picker;
          late Future<void> action;
          await tester.runAsync(() async {
            action = f.member('importCustomFont')() as Future<void>;
          });
          expect(f.picker.calls, hasLength(1));

          await tester.pumpWidget(const SizedBox.shrink());

          await tester.runAsync(p.publishB);

          SubtitleFontService.instance.resetProfileScope();
          SubtitleSettingsService.instance.resetProfileScope();

          playbackPreferences.writes.clear();
          picker.complete(
            FilePickerResult([
              PlatformFile(name: 'Late.ttf', path: source!.path, size: 1),
            ]),
          );
          await tester.runAsync(() => action);
          final font = ((await tester.runAsync(
            SubtitleFontService.instance.getCustomFonts,
          ))!).single;
          expect(
            playbackRawPreferences.getString(
              p.b.preferenceKey('subtitle_selected_font_id'),
            ),
            font.id,
          );
          expect(
            playbackRawPreferences.get(
              p.a.preferenceKey('subtitle_selected_font_id'),
            ),
            isNull,
          );
          expect(playbackPreferences.writes.map((w) => w.$1), [
            'subtitle_custom_fonts',
            p.b.preferenceKey('subtitle_selected_font_id'),
          ]);
          expect(
            await tester.runAsync(() => File(font.path!).exists()),
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.runAsync(
            () => SubtitleFontService.instance.removeCustomFont(font.id),
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());

          await tester.runAsync(p.close);
        }
      });
    },
  );
}
