import 'dart:io';

import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playback_settings_fixture.dart';

void main() {
  playbackHarness();
  testWidgets('video dropdown UI saves exact aspect value', (tester) async {
    await playbackCase(tester, (f) async {
      await f.mount(tester, section: PlaybackSettingsSection.video);
      final dropdown = find.byType(DropdownButton<int>).first;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      playbackPreferences.writes.clear();
      await tester.tap(find.text('Cover').last);
      await tester.pumpAndSettle();
      expect(f.member('defaultAspectIndex'), 1);
      expect(playbackPreferences.writes, [('player_default_aspect_index', 1)]);
      expect(playbackRawPreferences.getInt('player_default_aspect_index'), 1);
    });
  });
  testWidgets(
    'tvOS audio checkbox UI and directional boundaries preserve single stops',
    (tester) async {
      PlatformUtil.debugSetTvOS(true);
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.audio);
        final first = f.member('defaultAudioLangFocusNode') as FocusNode;
        final last = f.member('tvosLegacyAudioFocusNode') as FocusNode;
        first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNot(same(last)));
        last.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNot(same(first)));
        playbackPreferences.writes.clear();
        await tester.tap(find.text('Force stereo audio'));
        await tester.pumpAndSettle();
        expect(f.member('tvosForceStereo'), isTrue);
        expect(playbackPreferences.writes, [
          ('tvos_force_stereo_audio_v1', true),
        ]);
        for (final checkbox in find.byType(Checkbox).evaluate()) {
          expect(
            find.ancestor(
              of: find.byWidget(checkbox.widget),
              matching: find.byType(ExcludeFocus),
            ),
            findsOneWidget,
          );
        }
      });
    },
  );
  testWidgets(
    'macOS command text field retains owned focus and nonwrapping arrows',
    (tester) async {
      if (!Platform.isMacOS) return;
      PlatformUtil.debugSetAndroidTvCached(true);
      await playbackSeed({
        'default_player_mode': 'external',
        'external_player_preferred': 'custom_command',
      });
      await playbackCase(tester, (f) async {
        await f.mount(tester);
        final field = find.byType(TvTextField);
        expect(field, findsOneWidget);
        await tester.ensureVisible(field);
        final node = f.member('commandFocusNode') as FocusNode;
        node.requestFocus();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(node));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNot(same(node)));
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(node));
        expect(tester.widget<TvTextField>(field).shellRing, isFalse);
      });
    },
  );
  testWidgets('subtitle preview uses the player helper style for live values', (
    tester,
  ) async {
    await playbackCase(tester, (f) async {
      await f.mount(tester, section: PlaybackSettingsSection.subtitles);
      await f.member('setSubtitleSizeIndex')(2);
      await f.member('setSubtitleStyleIndex')(1);
      await f.member('setSubtitleColorIndex')(3);
      await f.member('setSubtitleBgIndex')(2);
      await f.member('setSubtitleBold')(true);
      await tester.pump();
      final data = SubtitleSettingsData(
        sizeIndex: 2,
        styleIndex: 1,
        colorIndex: 3,
        bgIndex: 2,
        bold: true,
        fontIndex: f.member('subtitleFontIndex') as int,
        fontFamily:
            (f.member('allFonts') as List)[f.member('subtitleFontIndex') as int]
                .fontFamily,
      );
      final expected = data.buildTextStyle(
        fontSizePx: SubtitleSize.options[2].sizePx * 0.4,
      );
      expect(tester.widget<Text>(find.text('Sample Subtitle')).style, expected);
    });
  });
}
