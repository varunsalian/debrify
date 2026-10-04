import 'dart:async';

import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../../../support/playback_settings_fixture.dart';
import '../../../../support/playback_settings_profiles.dart';

// A separate isolate: resetting SharedPreferences to hold its acquisition
// must not replace the stable device-prefs object used by font fixtures.
void main() {
  playbackHarness();
  testWidgets(
    'write held before preference acquisition captures incoming profile after pop',
    (tester) async {
      await playbackCase(tester, (f) async {
        final p = PlaybackProfiles();
        await tester.runAsync(() => p.open(f.directory));
        final held = Completer<void>();
        try {
          await f.mount(tester, section: PlaybackSettingsSection.video);
          final contents = {
            for (final k in playbackRawPreferences.getKeys())
              k: playbackRawPreferences.get(k)!,
          };
          SharedPreferences.setMockInitialValues({});
          playbackPreferences = PlaybackPreferences();
          SharedPreferencesStorePlatform.instance = playbackPreferences;
          await tester.runAsync(() async {
            for (final entry in contents.entries) {
              final v = entry.value;
              await playbackPreferences.setValue(
                v is bool
                    ? 'Bool'
                    : v is int
                    ? 'Int'
                    : v is String
                    ? 'String'
                    : 'StringList',
                'flutter.${entry.key}',
                v,
              );
            }
          });
          playbackPreferences.writes.clear();
          playbackPreferences.holdRead = held;
          final action = f.member('setDefaultAspectIndex')(2) as Future<void>;
          expect(f.member('defaultAspectIndex'), 2);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(p.publishB);
          expect(playbackPreferences.writes, isEmpty);
          held.complete();
          playbackPreferences.holdRead = null;
          await tester.runAsync(() => action);
          playbackRawPreferences = (await tester.runAsync(
            SharedPreferences.getInstance,
          ))!;
          expect(playbackPreferences.writes, [
            (p.b.preferenceKey('player_default_aspect_index'), 2),
          ]);
          expect(
            playbackRawPreferences.get(
              p.a.preferenceKey('player_default_aspect_index'),
            ),
            isNull,
          );
          expect(
            playbackRawPreferences.get(
              p.b.preferenceKey('player_default_aspect_index'),
            ),
            2,
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (!held.isCompleted) held.complete();
          playbackPreferences.holdRead = null;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(p.close);
        }
      });
    },
  );
}
