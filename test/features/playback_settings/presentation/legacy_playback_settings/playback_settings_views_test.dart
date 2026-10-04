import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/settings/player_dock_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/play_loader_style_page.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/subtitle_priority_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playback_settings_fixture.dart';

const requireLinux = bool.fromEnvironment(
  'PLAYBACK_SETTINGS_REQUIRE_ORIGINAL_LINUX',
  defaultValue: false,
);
const captureLinux = bool.fromEnvironment(
  'PLAYBACK_SETTINGS_CAPTURE_ORIGINAL_LINUX',
  defaultValue: false,
);

void main() {
  playbackHarness();
  final sections = <PlaybackSettingsSection, String>{
    PlaybackSettingsSection.player: 'Default Player',
    PlaybackSettingsSection.video: 'Default Aspect',
    PlaybackSettingsSection.audio: 'Default Audio',
    PlaybackSettingsSection.subtitles: 'Sample Subtitle',
  };
  for (final entry in sections.entries) {
    testWidgets('section routing ${entry.key.name}', (tester) async {
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: entry.key);
        final header = tester.widget<SettingsPageHeader>(
          find.byType(SettingsPageHeader),
        );
        expect(header.title, entry.key.label);
        expect(header.subtitle, entry.key.description);
        for (final other in sections.entries) {
          expect(
            find.text(other.value),
            other.key == entry.key ? findsOneWidget : findsNothing,
          );
        }
      });
    });
  }
  for (final mode in ['external', 'deovr']) {
    for (final section in PlaybackSettingsSection.values.where(
      (s) => s != PlaybackSettingsSection.player,
    )) {
      testWidgets('managed category $mode ${section.name} uses State callback', (
        tester,
      ) async {
        await playbackSeed({'default_player_mode': mode});
        await playbackCase(tester, (f) async {
          await f.mount(tester, section: section);
          expect(
            find.text(
              '${mode == 'deovr' ? 'DeoVR' : 'Your external player'} manages these settings. Choose Debrify Player to configure its defaults.',
            ),
            findsOneWidget,
          );
          expect(find.text(sections[section]!), findsNothing);
          final tile = tester.widget<SettingsTile>(
            find.widgetWithText(SettingsTile, 'Choose player'),
          );
          expect(tile.onTap, f.member('openPlayerSettings'));
        });
      });
    }
  }
  testWidgets(
    'spinner while original renderer read is held; unmount remains guarded',
    (tester) async {
      await playbackCase(tester, (f) async {
        final held = Completer<void>();
        playbackPreferences.holdWrite = held;
        await f.mount(
          tester,
          section: PlaybackSettingsSection.video,
          wait: false,
        );
        await f.until(tester, () => playbackPreferences.writes.isNotEmpty);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(f.member('loading'), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        held.complete();
        playbackPreferences.holdWrite = null;
        for (var i = 0; i < 10; i++) {
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      });
    },
  );
  testWidgets('storage throw clears spinner and preserves raw load message', (
    tester,
  ) async {
    await playbackSeed({'default_player_mode': 1});
    await playbackCase(tester, (f) async {
      await f.mount(tester, section: PlaybackSettingsSection.video);
      expect(f.member('loading'), isFalse);
      expect(find.textContaining('Failed to load settings:'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
  for (final section in PlaybackSettingsSection.values) {
    testWidgets('tvOS detection is player-only ${section.name}', (
      tester,
    ) async {
      PlatformUtil.debugSetTvOS(true);
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: section);
        expect(
          f.tvCalls.map((c) => c.method),
          section == PlaybackSettingsSection.player
              ? everyElement('canOpen')
              : isEmpty,
        );
        expect(
          f.tvCalls.map((c) => c.arguments).toList(),
          section == PlaybackSettingsSection.player
              ? iOSExternalPlayer.values
                    .where(
                      (p) =>
                          p != iOSExternalPlayer.customScheme &&
                          p.availableOnTvos,
                    )
                    .map((p) => p.urlScheme)
                    .toList()
              : <String>[],
        );
        if (section == PlaybackSettingsSection.player) {
          expect(
            (f.member(
                  Platform.isMacOS
                      ? 'installedPlayers'
                      : 'installedLinuxPlayers',
                )
                as Map),
            isNotEmpty,
          );
        }
        expect(f.urls.schemes, isEmpty);
        expect(f.member('isAndroidTv'), isFalse);
      });
    });
  }
  testWidgets(
    'TV entry seeds the first row and concrete focus is retained on reload',
    (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      await playbackCase(tester, (f) async {
        await f.mount(tester, section: PlaybackSettingsSection.video);
        final aspect = f.member('aspectFocusNode') as FocusNode;
        expect(FocusManager.instance.primaryFocus, same(aspect));
        await tester.runAsync(() async => await f.member('loadSettings')());
        await f.loaded(tester);
        expect(FocusManager.instance.primaryFocus, same(aspect));
      });
    },
  );
  testWidgets('mode rows are single stops and dropdown arrows do not wrap', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    await playbackCase(tester, (f) async {
      await f.mount(tester);
      expect(
        FocusManager.instance.primaryFocus,
        same(f.member('firstModeFocusNode')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      expect(find.byType(Radio<String>), findsNWidgets(3));
      for (final radio in find.byType(Radio<String>).evaluate()) {
        expect(
          find.ancestor(
            of: find.byWidget(radio.widget),
            matching: find.byType(ExcludeFocus),
          ),
          findsOneWidget,
        );
      }
    });
  });
  final destinations = <(String, Type)>[
    ('Player Controls', PlayerDockPage),
    ('Player Guide', PlayerGuideStylePage),
    ('Play Loader', PlayLoaderStylePage),
    ('Subtitle priority', SubtitlePriorityPage),
  ];
  for (final destination in destinations) {
    testWidgets('appearance route ${destination.$1}', (tester) async {
      await playbackCase(tester, (f) async {
        await f.mount(
          tester,
          section: destination.$2 == SubtitlePriorityPage
              ? PlaybackSettingsSection.subtitles
              : PlaybackSettingsSection.player,
        );
        final label = find.text(destination.$1);
        await tester.ensureVisible(label);
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(find.byType(destination.$2), findsOneWidget);
        f.navigator.currentState!.pop();
        await tester.pumpAndSettle();
      });
    });
  }
  for (final view in [
    'player',
    'video',
    'audio',
    'subtitles',
    'managed_video',
  ]) {
    testWidgets('reachable pixel golden $view', (tester) async {
      if (Platform.isLinux && !captureLinux && !requireLinux) {
        // Strict missing-file failure is enabled after original capture verification.
        markTestSkipped(
          'Original Linux capture pending before layout extraction',
        );
        return;
      }
      if (view == 'managed_video') {
        await playbackSeed({'default_player_mode': 'external'});
      }
      await playbackCase(tester, (f) async {
        await f.mount(
          tester,
          section: PlaybackSettingsSection.values.byName(
            view == 'managed_video' ? 'video' : view,
          ),
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('playback-canvas')),
          matchesGoldenFile(
            '../../../../goldens/playback_settings/${Platform.isLinux ? 'linux' : 'macos'}/$view.png',
          ),
        );
      });
    });
  }
}
