import 'package:debrify/screens/settings/external_player_settings_page.dart';
import 'package:debrify/screens/settings/playback_settings_page.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Native application discovery uses real asynchronous I/O on desktop. Let it
// finish outside the widget test's fake clock before checking the loaded page.
Future<void> settleSettings(WidgetTester tester) async {
  await tester.runAsync(() => tester.pump(const Duration(milliseconds: 350)));
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (i >= 5 &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlatformUtil.debugSetTvOS(false);
    PlatformUtil.debugSetAndroidTvCached(false);
  });
  tearDown(() {
    PlatformUtil.debugSetTvOS(null);
    PlatformUtil.debugSetAndroidTvCached(null);
  });

  testWidgets('Playback contains four categories and back returns to the hub', (
    tester,
  ) async {
    await tester.runAsync(
      () => tester.pumpWidget(const MaterialApp(home: PlaybackSettingsPage())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsTile), findsNWidgets(4));
    expect(find.text('Default Aspect'), findsNothing);
    for (final section in PlaybackSettingsSection.values) {
      await tester.tap(
        find.byKey(ValueKey('playback-category-${section.name}')),
      );
      await settleSettings(tester);
      expect(
        tester
            .widget<ExternalPlayerSettingsPage>(
              find.byType(ExternalPlayerSettingsPage),
            )
            .section,
        section,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsTile), findsNWidgets(4));
    }
  });

  testWidgets(
    'each built-in control stays in its category and saves the existing preference',
    (tester) async {
      const expected = {
        PlaybackSettingsSection.player: [
          'Default Player',
          'Mark movies watched at',
          'Mark episodes watched at',
          'Skip intros & credits',
          'Timestamp provider',
          'Connection patience',
          'Stream buffer',
          'Player Controls',
          'Player Guide',
          'Play Loader',
        ],
        PlaybackSettingsSection.video: ['Default Aspect'],
        PlaybackSettingsSection.audio: ['Default Audio'],
        PlaybackSettingsSection.subtitles: [
          'Default Subtitle',
          'Size',
          'Style',
          'Color',
          'Background',
          'Font',
          'Bold',
          'Import Custom Font (TTF/OTF)',
          'Sample Subtitle',
        ],
      };
      for (final section in PlaybackSettingsSection.values) {
        await tester.runAsync(
          () => tester.pumpWidget(
            MaterialApp(
              home: ExternalPlayerSettingsPage(
                key: ValueKey(section),
                section: section,
              ),
            ),
          ),
        );
        await settleSettings(tester);
        for (final entry in expected.entries) {
          for (final label in entry.value) {
            expect(
              find.text(label),
              entry.key == section ? findsOneWidget : findsNothing,
              reason:
                  '$label belongs to ${entry.key.name}, viewing ${section.name}',
            );
          }
        }
        if (section == PlaybackSettingsSection.audio) {
          final dropdown = find.byType(DropdownButton<int>);
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text('English').last);
          await tester.pumpAndSettle();
          expect(await StorageService.getDefaultAudioLanguage(), 'en');
        }
      }
    },
  );

  testWidgets(
    'Apple TV hides unsupported player controls but keeps guide and loader shortcuts',
    (tester) async {
      PlatformUtil.debugSetTvOS(true);
      await tester.runAsync(
        () => tester.pumpWidget(
          const MaterialApp(home: ExternalPlayerSettingsPage()),
        ),
      );
      await settleSettings(tester);
      expect(find.text('Player Controls'), findsNothing);
      expect(find.text('Style, colour and size'), findsNothing);
      expect(find.text('Debrify TV Player'), findsNothing);
      expect(find.text('Player Guide'), findsOneWidget);
      expect(find.text('Play Loader'), findsOneWidget);
    },
  );

  testWidgets(
    'Apple TV keeps video and audio compatibility options in their categories',
    (tester) async {
      PlatformUtil.debugSetTvOS(true);
      await tester.runAsync(
        () => tester.pumpWidget(
          const MaterialApp(
            home: ExternalPlayerSettingsPage(
              section: PlaybackSettingsSection.audio,
            ),
          ),
        ),
      );
      await settleSettings(tester);
      for (final label in [
        'Multichannel audio (LPCM over HDMI)',
        'Force stereo audio',
        'Use the previous audio engine',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Force software video decoding'), findsNothing);
      await tester.runAsync(
        () => tester.pumpWidget(
          const MaterialApp(
            home: ExternalPlayerSettingsPage(
              key: ValueKey('video'),
              section: PlaybackSettingsSection.video,
            ),
          ),
        ),
      );
      await settleSettings(tester);
      expect(find.text('Force software video decoding'), findsOneWidget);
      expect(find.text('Force stereo audio'), findsNothing);
    },
  );

  testWidgets(
    'external mode explains ownership and changing player refreshes the category',
    (tester) async {
      await StorageService.setDefaultPlayerMode('external');
      await tester.runAsync(
        () => tester.pumpWidget(
          const MaterialApp(
            home: ExternalPlayerSettingsPage(
              section: PlaybackSettingsSection.audio,
            ),
          ),
        ),
      );
      await settleSettings(tester);
      expect(find.textContaining('manages these settings'), findsOneWidget);
      expect(find.text('Default Audio'), findsNothing);
      await tester.tap(find.text('Choose player'));
      await settleSettings(tester);
      await tester.tap(find.text('Debrify Player'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await settleSettings(tester);
      expect(find.text('Default Audio'), findsOneWidget);
      expect(await StorageService.getDefaultPlayerMode(), 'debrify');
    },
  );

  testWidgets(
    'TV focus enters a category, activates its first control, and returns to its row',
    (tester) async {
      PlatformUtil.debugSetTvOS(true);
      await tester.runAsync(
        () =>
            tester.pumpWidget(const MaterialApp(home: PlaybackSettingsPage())),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'playback-player-category',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSettings(tester);
      expect(find.text('Default Aspect'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Cinema Zoom'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final node = FocusManager.instance.primaryFocus;
      expect(node, isNotNull);
      expect(node, isNot(isA<FocusScopeNode>()));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSettings(tester);
      expect(find.text('Default Aspect'), findsOneWidget);
    },
  );
}
