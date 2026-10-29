import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/lib_source.dart';

// Complements the executable projection/Activity tests and device smoke test:
// guard the caller routing, especially terminal failures versus fallback.
void main() {
  final bridge = File(
    'lib/services/android_tv_player_bridge.dart',
  ).readAsStringSync();
  final launcher =
      File('lib/services/video_player_launcher.dart').readAsStringSync() +
      Directory('lib/features/player_launch')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');
  // The whole Debrify TV screen: its facade plus every feature file.
  final magic = libJoined(
    libSourceSet(
      files: ['lib/screens/magic_tv_screen.dart'],
      directories: ['lib/features/debrify_tv'],
    ),
  );

  test(
    'all three bridge launches bind profile ownership and refresh before handoff',
    () {
      for (final name in [
        'launchTorboxPlayback',
        'launchRealDebridPlayback',
        'launchTorrentPlayback',
      ]) {
        final start = bridge.indexOf('static Future<bool> $name(');
        final end = bridge.indexOf('\n  static ', start + 1);
        final body = bridge.substring(start, end);
        expect(
          body.indexOf('final launchScope = ProfileRuntime.scope.value'),
          lessThan(body.indexOf('await ')),
        );
        expect(body, contains('NativeProfileProjection.withPlayerLaunch('));
        expect(body, contains("'nativePlayerProfile':"));
        expect(body, contains('on NativePlayerSettingsUnavailable catch'));
        // Cleanup occurs before the terminal error is returned to the UI.
        expect(
          body.indexOf('if (settingsFailure != null) throw settingsFailure'),
          greaterThan(body.lastIndexOf(' = null;')),
        );
      }
    },
  );

  test('native settings rejections cannot silently become Flutter playback', () {
    expect(
      launcher,
      contains('on NativePlayerSettingsUnavailable catch (error)'),
    );
    expect(
      'if (e is NativePlayerSettingsUnavailable) rethrow;'
          .allMatches(launcher)
          .length,
      2,
    );
    expect(
      'if (e is NativePlayerSettingsUnavailable) rethrow;'
          .allMatches(magic)
          .length,
      3,
    );
    // Every direct Debrify TV helper call sits inside a terminal-error handler:
    // ten ordinary watch paths plus the early-search launch path.
    expect(
      'on NativePlayerSettingsUnavailable catch (error)'
          .allMatches(magic)
          .length,
      10,
    );
    expect(
      magic,
      contains(
        'if (e is NativePlayerSettingsUnavailable) {\n        _sections.feedback.showNativeSettingsFailure(e);\n        return;',
      ),
    );
  });
}
