import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playback_settings_fixture.dart';

void main() {
  playbackHarness();
  testWidgets('player mode saves before State publication', (tester) async {
    await playbackCase(tester, (f) async {
      await f.mount(tester, section: PlaybackSettingsSection.video);
      playbackPreferences.writes.clear();
      final held = Completer<void>();
      playbackPreferences.holdWrite = held;
      final action =
          f.member('setDefaultPlayerMode')('external') as Future<void>;
      await f.until(tester, () => playbackPreferences.writes.isNotEmpty);
      try {
        expect(f.member('defaultPlayerMode'), 'debrify');
        expect(playbackPreferences.writes, [
          ('default_player_mode', 'external'),
        ]);
      } finally {
        held.complete();
      }
      await action;
      playbackPreferences.holdWrite = null;
      expect(f.member('defaultPlayerMode'), 'external');
    });
  });
  final selections = <(String, Object, String, String, String)>[
    (
      'selectPlayer',
      ExternalPlayer.vlc,
      'external_player_preferred',
      'vlc',
      'selectedPlayer',
    ),
    (
      'selectIOSPlayer',
      iOSExternalPlayer.infuse,
      'ios_external_player_preferred',
      'infuse',
      'selectedIOSPlayer',
    ),
    (
      'selectLinuxPlayer',
      LinuxExternalPlayer.mpv,
      'linux_external_player_preferred',
      'mpv',
      'selectedLinuxPlayer',
    ),
    (
      'selectWindowsPlayer',
      WindowsExternalPlayer.vlc,
      'windows_external_player_preferred',
      'vlc',
      'selectedWindowsPlayer',
    ),
  ];
  for (final c in selections) {
    testWidgets('${c.$1} saves exact existing preference', (tester) async {
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.video);
        playbackPreferences.writes.clear();
        await f.member(c.$1)(c.$2);
        expect(playbackPreferences.writes, [(c.$3, c.$4)]);
        expect(playbackRawPreferences.get(c.$3), c.$4);
        expect(f.member(c.$5), c.$2);
      });
    });
  }
  for (final cancel in [false, true]) {
    testWidgets(
      'macOS app browse exact picker and ordered writes cancel=$cancel',
      (tester) async {
        await playbackCase(tester, (f) async {
          await f.mount(tester, section: PlaybackSettingsSection.video);
          f.picker.result = cancel
              ? null
              : FilePickerResult([
                  PlatformFile(
                    name: 'Fixture.app',
                    path: '/Applications/Fixture.app',
                    size: 0,
                  ),
                ]);
          playbackPreferences.writes.clear();
          await f.member('browseForCustomApp')();
          expect(f.picker.calls, [
            {
              'type': FileType.custom,
              'allowMultiple': false,
              'allowedExtensions': ['app'],
              'dialogTitle': 'Select Video Player Application',
            },
          ]);
          expect(
            playbackPreferences.writes,
            cancel
                ? <(String, Object?)>[]
                : [
                    (
                      'external_player_custom_path',
                      '/Applications/Fixture.app',
                    ),
                    ('external_player_custom_name', 'Fixture'),
                    ('external_player_preferred', 'custom_app'),
                  ],
          );
          if (!cancel) {
            expect(f.member('customAppPath'), '/Applications/Fixture.app');
            expect(f.member('customAppName'), 'Fixture');
            expect(f.member('selectedPlayer'), ExternalPlayer.customApp);
            playbackPreferences.writes.clear();
            await f.member('clearCustomApp')();
            expect(playbackPreferences.writes, [
              ('external_player_custom_path', null),
              ('external_player_custom_name', null),
              ('external_player_preferred', 'system_default'),
            ]);
            expect(f.member('customAppPath'), isNull);
            expect(f.member('customAppName'), isNull);
            expect(f.member('selectedPlayer'), ExternalPlayer.systemDefault);
            expect(find.byType(AlertDialog), findsNothing);
          }
        });
      },
    );
  }
  final commands =
      <(String, String, String, String, String, String, String, String)>[
        (
          'saveCustomCommand',
          'clearCustomCommand',
          'commandController',
          'commandError',
          'customCommand',
          'external_player_custom_command',
          'external_player_preferred',
          'vlc {url}',
        ),
        (
          'saveIOSCustomScheme',
          'clearIOSCustomScheme',
          'iosSchemeController',
          'iosSchemeError',
          'iosCustomScheme',
          'ios_custom_scheme_template',
          'ios_external_player_preferred',
          'fixture://play?url={url}',
        ),
        (
          'saveLinuxCustomCommand',
          'clearLinuxCustomCommand',
          'linuxCommandController',
          'linuxCommandError',
          'linuxCustomCommand',
          'linux_custom_command',
          'linux_external_player_preferred',
          'mpv {url}',
        ),
        (
          'saveWindowsCustomCommand',
          'clearWindowsCustomCommand',
          'windowsCommandController',
          'windowsCommandError',
          'windowsCustomCommand',
          'windows_custom_command',
          'windows_external_player_preferred',
          'vlc {url}',
        ),
      ];
  for (final c in commands) {
    testWidgets('${c.$1} invalid valid clear preserves order and controller', (
      tester,
    ) async {
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.video);
        final controller = f.member(c.$3) as TextEditingController;
        controller.text = 'invalid';
        playbackPreferences.writes.clear();
        await f.member(c.$1)();
        expect(playbackPreferences.writes, isEmpty);
        expect(f.member(c.$4), isNotNull);
        controller.text = '  ${c.$8}  ';
        await f.member(c.$1)();
        expect(playbackPreferences.writes, [
          (c.$6, c.$8),
          (
            c.$7,
            c.$1 == 'saveIOSCustomScheme' ? 'custom_scheme' : 'custom_command',
          ),
        ]);
        expect(f.member(c.$5), c.$8);
        expect(f.member(c.$4), isNull);
        await tester.pump();
        expect(
          find.text(
            c.$1 == 'saveIOSCustomScheme'
                ? 'Custom URL scheme saved'
                : 'Custom command saved',
          ),
          findsOneWidget,
        );
        playbackPreferences.writes.clear();
        await f.member(c.$2)();
        expect(playbackPreferences.writes, [
          (c.$6, null),
          (c.$7, c.$1 == 'saveIOSCustomScheme' ? 'vlc' : 'system_default'),
        ]);
        expect(controller.text, '');
        expect(f.member(c.$5), isNull);
        expect(f.member(c.$4), isNull);
        expect(find.byType(AlertDialog), findsNothing);
      });
    });
  }
  for (final name in [
    'wrong.txt',
    'missing.ttf',
    'Fixture.ttf',
    'NoExtension',
  ]) {
    testWidgets('font import and cleanup isolated $name', (tester) async {
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.subtitles);
        final original = await SubtitleFontService.instance.getCustomFonts();
        expect(original, isEmpty);
        final source = File('${f.directory.path}/$name');
        await tester.runAsync(
          () => File('assets/fonts/Roboto-Regular.ttf').copy(source.path),
        );
        f.picker.result = FilePickerResult([
          PlatformFile(
            name: name,
            path: name == 'missing.ttf' ? null : source.path,
            size: 1,
          ),
        ]);
        playbackPreferences.writes.clear();
        await tester.runAsync(() async => await f.member('importCustomFont')());
        await tester.pump();
        expect(f.picker.calls, [
          {
            'type': FileType.any,
            'allowMultiple': false,
            'allowedExtensions': null,
            'dialogTitle': null,
          },
        ]);
        if (name == 'wrong.txt' || name == 'missing.ttf') {
          expect(await SubtitleFontService.instance.getCustomFonts(), isEmpty);
          expect(playbackPreferences.writes, isEmpty);
          expect(
            find.text(
              name == 'wrong.txt'
                  ? 'Please select a .ttf or .otf font file'
                  : 'Could not access selected file',
            ),
            findsOneWidget,
          );
          expect(
            await tester.runAsync(
              () => Directory('${f.directory.path}/subtitle_fonts').exists(),
            ),
            isFalse,
          );
        } else {
          final fonts = await SubtitleFontService.instance.getCustomFonts();
          expect(fonts, hasLength(1));
          final font = fonts.single;
          expect(font.path, startsWith('${f.directory.path}/subtitle_fonts/'));
          expect(
            await tester.runAsync(() => File(font.path!).readAsBytes()),
            await tester.runAsync(source.readAsBytes),
          );
          expect(
            f.member('subtitleFontIndex'),
            SubtitleFont.builtInOptions.length,
          );
          expect((f.member('allFonts') as List).last, same(font));
          expect(
            find.text('Font "${font.label}" imported successfully'),
            findsOneWidget,
          );
          ScaffoldMessenger.of(
            tester.element(find.text('Sample Subtitle')),
          ).removeCurrentSnackBar();
          await tester.pump();
          await tester.runAsync(
            () async => await f.member('removeCustomFont')(font),
          );
          await tester.pump();
          expect(await SubtitleFontService.instance.getCustomFonts(), isEmpty);
          expect(
            await tester.runAsync(() => File(font.path!).exists()),
            isFalse,
          );
          expect(
            playbackRawPreferences.getString('subtitle_selected_font_id'),
            'default',
          );
          expect(f.member('subtitleFontIndex'), 0);
          await tester.pumpAndSettle();
          expect(find.text('Font "${font.label}" removed'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
        }
      });
    });
  }
}
