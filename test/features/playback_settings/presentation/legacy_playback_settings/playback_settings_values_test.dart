import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playback_settings_fixture.dart';

void main() {
  playbackHarness();
  for (final section in PlaybackSettingsSection.values) {
    for (final renderer in <String?>[null, 'direct_surface', 'automatic']) {
      for (final elevation in [0, 2]) {
        testWidgets(
          'ordered open migrations ${section.name} renderer=$renderer elevation=$elevation',
          (tester) async {
            await playbackSeed({
              if (renderer != null) 'android_video_renderer_mode': renderer,
              'subtitle_elevation_index': elevation,
            });
            await playbackCase(tester, (f) async {
              await f.mount(tester, section: section);
              final expected = <(String, Object?)>[
                if (renderer != 'automatic')
                  ('android_video_renderer_mode', 'direct_mediacodec'),
                ('android_video_renderer_gpu_migration_v1', true),
                if (elevation == 0)
                  ('subtitle_elevation_index', SubtitleElevation.defaultIndex),
                ('subtitle_extreme_bottom_default_adopted_v1', true),
              ];
              expect(playbackPreferences.writes, expected);
              expect(
                playbackRawPreferences.getInt('subtitle_elevation_index'),
                elevation == 0 ? SubtitleElevation.defaultIndex : elevation,
              );
              playbackPreferences.writes.clear();
              await tester.runAsync(
                () async => await f.member('loadSettings')(),
              );
              await f.loaded(tester);
              expect(playbackPreferences.writes, isEmpty);
            });
          },
        );
      }
    }
  }

  // Independent expected key/value table: all 33 original instant-save setters.
  final cases = <(String, Object, String, Object, String, Object)>[
    (
      'setVrDefaultScreenType',
      'sphere',
      'quick_play_vr_default_screen_type',
      'sphere',
      'vrDefaultScreenType',
      'sphere',
    ),
    (
      'setVrDefaultStereoMode',
      'tb',
      'quick_play_vr_default_stereo_mode',
      'tb',
      'vrDefaultStereoMode',
      'tb',
    ),
    (
      'setVrAutoDetectFormat',
      false,
      'quick_play_vr_auto_detect_format',
      false,
      'vrAutoDetectFormat',
      false,
    ),
    (
      'setVrShowDialog',
      false,
      'quick_play_vr_show_dialog',
      false,
      'vrShowDialog',
      false,
    ),
    (
      'setDefaultAspectIndex',
      1,
      'player_default_aspect_index',
      1,
      'defaultAspectIndex',
      1,
    ),
    ('setNightModeIndex', 2, 'player_night_mode_index', 2, 'nightModeIndex', 2),
    (
      'setSystemAudioEffects',
      true,
      'player_system_audio_effects',
      true,
      'systemAudioEffects',
      true,
    ),
    (
      'setTvosForceSoftwareDecode',
      true,
      'tvos_force_software_decode',
      true,
      'tvosForceSoftwareDecode',
      true,
    ),
    (
      'setTvosForceStereo',
      true,
      'tvos_force_stereo_audio_v1',
      true,
      'tvosForceStereo',
      true,
    ),
    (
      'setTvosLegacyAudioOutput',
      true,
      'tvos_legacy_audio_output_v1',
      true,
      'tvosLegacyAudioOutput',
      true,
    ),
    (
      'setAudioPassthrough',
      true,
      'player_audio_passthrough',
      true,
      'audioPassthrough',
      true,
    ),
    (
      'setAppleMultichannel',
      true,
      'player_apple_multichannel_audio',
      true,
      'appleMultichannel',
      true,
    ),
    (
      'setAndroidVideoRendererMode',
      'automatic',
      'android_video_renderer_mode',
      'automatic',
      'androidVideoRendererMode',
      AndroidVideoRendererMode.automatic,
    ),
    (
      'setContentDisplayMatchMode',
      'frame_rate',
      'content_display_match_mode',
      'frame_rate',
      'contentDisplayMatchMode',
      ContentDisplayMatchMode.frameRate,
    ),
    (
      'setIptvDecoderMode',
      'software',
      'iptv_decoder_mode',
      'software',
      'iptvDecoderMode',
      'software',
    ),
    (
      'setStartPortrait',
      true,
      'player_start_portrait',
      true,
      'startPortrait',
      true,
    ),
    (
      'setSubtitleOnlyForeignAudio',
      true,
      'subtitle_only_foreign_audio',
      true,
      'subtitleOnlyForeignAudio',
      true,
    ),
    (
      'setSubtitleForcedOnly',
      true,
      'subtitle_forced_only',
      true,
      'subtitleForcedOnly',
      true,
    ),
    (
      'setSubtitleAutoSync',
      true,
      'subtitle_auto_sync_enabled',
      true,
      'subtitleAutoSync',
      true,
    ),
    (
      'setMovieCompletionThresholdIndex',
      1,
      'movie_completion_threshold',
      60,
      'movieCompletionThreshold',
      60,
    ),
    (
      'setEpisodeCompletionThresholdIndex',
      3,
      'episode_completion_threshold',
      75,
      'episodeCompletionThreshold',
      75,
    ),
    (
      'setSkipSegmentsEnabled',
      false,
      'skip_segments_enabled',
      false,
      'skipSegmentsEnabled',
      false,
    ),
    (
      'setSkipSegmentProvider',
      'introdb',
      'skip_segment_provider',
      'introdb',
      'skipSegmentProvider',
      'introdb',
    ),
    (
      'setNetPatience',
      'patient',
      'network_connect_patience',
      'patient',
      'netPatience',
      'patient',
    ),
    (
      'setNetBuffer',
      'huge',
      'network_buffer_size',
      'huge',
      'netBuffer',
      'huge',
    ),
    (
      'setDefaultSubtitleLanguage',
      'es',
      'player_default_subtitle_language',
      'es',
      'defaultSubtitleLanguage',
      'es',
    ),
    (
      'setDefaultAudioLanguage',
      'fr',
      'player_default_audio_language',
      'fr',
      'defaultAudioLanguage',
      'fr',
    ),
    (
      'setSubtitleSizeIndex',
      3,
      'subtitle_size_index',
      3,
      'subtitleSizeIndex',
      3,
    ),
    (
      'setSubtitleStyleIndex',
      2,
      'subtitle_style_index',
      2,
      'subtitleStyleIndex',
      2,
    ),
    (
      'setSubtitleColorIndex',
      1,
      'subtitle_color_index',
      1,
      'subtitleColorIndex',
      1,
    ),
    ('setSubtitleBgIndex', 2, 'subtitle_bg_index', 2, 'subtitleBgIndex', 2),
    (
      'setSubtitleFontIndex',
      1,
      'subtitle_selected_font_id',
      'roboto',
      'subtitleFontIndex',
      1,
    ),
    ('setSubtitleBold', true, 'subtitle_bold', true, 'subtitleBold', true),
  ];
  for (final c in cases) {
    testWidgets('${c.$1} publishes before ordered persisted writes', (
      tester,
    ) async {
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.subtitles);
        playbackPreferences.writes.clear();
        final held = Completer<void>();
        playbackPreferences.holdWrite = held;
        final future = f.member(c.$1)(c.$2) as Future<void>;
        await f.until(tester, () => playbackPreferences.writes.isNotEmpty);
        try {
          expect(
            f.member(c.$5),
            c.$6,
            reason: 'setState must precede the held first write',
          );
          expect(playbackPreferences.writes.first, (c.$3, c.$4));
        } finally {
          held.complete();
        }
        await future;
        playbackPreferences.holdWrite = null;
        expect(playbackPreferences.writes, <(String, Object?)>[
          (c.$3, c.$4),
          if (c.$1 == 'setAndroidVideoRendererMode')
            ('android_video_renderer_gpu_migration_v1', true),
        ]);
        expect(playbackRawPreferences.get(c.$3), c.$4);
        expect(f.member(c.$5), c.$6);
      });
    });
  }
  testWidgets('language null removes the same keys', (tester) async {
    await playbackCase(tester, (f) async {
      await f.mount(tester, section: PlaybackSettingsSection.audio);
      await f.member('setDefaultAudioLanguage')('fr');
      await f.member('setDefaultSubtitleLanguage')('es');
      playbackPreferences.writes.clear();
      await f.member('setDefaultAudioLanguage')(null);
      await f.member('setDefaultSubtitleLanguage')(null);
      expect(playbackPreferences.writes, [
        ('player_default_audio_language', null),
        ('player_default_subtitle_language', null),
      ]);
      expect(f.member('defaultAudioLanguage'), isNull);
      expect(f.member('defaultSubtitleLanguage'), isNull);
    });
  });
  for (final section in PlaybackSettingsSection.values) {
    testWidgets('seeded load snapshots and fallback ${section.name}', (
      tester,
    ) async {
      await playbackSeed({
        'player_default_aspect_index': 1,
        'player_night_mode_index': 2,
        'player_system_audio_effects': true,
        'player_start_portrait': true,
        'android_video_renderer_mode': 'automatic',
        'android_video_renderer_gpu_migration_v1': true,
        'content_display_match_mode': 'frame_rate',
        'iptv_decoder_mode': 'software',
        'subtitle_only_foreign_audio': true,
        'subtitle_forced_only': true,
        'subtitle_auto_sync_enabled': true,
        'movie_completion_threshold': 60,
        'episode_completion_threshold': 75,
        'skip_segments_enabled': false,
        'skip_segment_provider': 'future',
        'player_default_subtitle_language': 'es',
        'player_default_audio_language': 'fr',
        'network_connect_patience': 'future',
        'network_buffer_size': 'future',
        'subtitle_size_index': 3,
        'subtitle_style_index': 2,
        'subtitle_color_index': 1,
        'subtitle_bg_index': 2,
        'subtitle_bold': true,
        'subtitle_selected_font_id': 'roboto',
        'subtitle_extreme_bottom_default_adopted_v1': true,
      });
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: section);
        final expected = <String, Object?>{
          'loading': false,
          'defaultPlayerMode': 'debrify',
          'isAndroidTv': false,
          'defaultAspectIndex': 1,
          'nightModeIndex': 2,
          'systemAudioEffects': true,
          'startPortrait': true,
          'androidVideoRendererMode': AndroidVideoRendererMode.automatic,
          'contentDisplayMatchMode': ContentDisplayMatchMode.frameRate,
          'iptvDecoderMode': 'software',
          'subtitleOnlyForeignAudio': true,
          'subtitleForcedOnly': true,
          'subtitleAutoSync': true,
          'movieCompletionThreshold': 60,
          'episodeCompletionThreshold': 75,
          'skipSegmentsEnabled': false,
          'skipSegmentProvider': 'auto',
          'defaultSubtitleLanguage': 'es',
          'defaultAudioLanguage': 'fr',
          'netPatience': 'standard',
          'netBuffer': 'standard',
          'subtitleSizeIndex': 3,
          'subtitleStyleIndex': 2,
          'subtitleColorIndex': 1,
          'subtitleBgIndex': 2,
          'subtitleFontIndex': 1,
          'subtitleBold': true,
          'tvosForceSoftwareDecode': false,
          'tvosForceStereo': false,
          'tvosLegacyAudioOutput': false,
          'audioPassthrough': false,
          'appleMultichannel': false,
          'vrDefaultScreenType': 'dome',
          'vrDefaultStereoMode': 'sbs',
          'vrAutoDetectFormat': true,
          'vrShowDialog': true,
        };
        expect({for (final k in expected.keys) k: f.access[k]}, expected);
        expect(
          (f.member('allFonts') as List<SubtitleFont>).map((f) => f.id),
          SubtitleFont.builtInOptions.map((f) => f.id),
        );
        expect(playbackPreferences.writes, isEmpty);
      });
    });
  }
  testWidgets(
    'a focus change publishes its owned ring flag and resources dispose',
    (tester) async {
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.video);
        final node = f.member('aspectFocusNode') as FocusNode;
        node.requestFocus();
        await tester.pump();
        expect(f.member('aspectFocused'), isTrue);
        final controller =
            f.member('commandController') as TextEditingController;
        await tester.pumpWidget(const SizedBox.shrink());
        expect(() => controller.addListener(() {}), throwsFlutterError);
        expect(() => node.addListener(() {}), throwsFlutterError);
      });
    },
  );
}
