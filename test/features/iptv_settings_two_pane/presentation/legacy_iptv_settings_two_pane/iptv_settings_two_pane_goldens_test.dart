import 'dart:io';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_settings_two_pane_fixture.dart';

void main() {
  const reverse = bool.fromEnvironment(
    'IPTV_SETTINGS_TWO_PANE_REVERSE_GOLDENS',
  );
  const captureLinux = bool.fromEnvironment(
    'IPTV_SETTINGS_TWO_PANE_CAPTURE_ORIGINAL_LINUX',
  );
  const requireLinux = bool.fromEnvironment(
    'IPTV_SETTINGS_TWO_PANE_REQUIRE_ORIGINAL_LINUX',
  );
  final scenes = [
    'add_file',
    'channel_lists',
    'startup_pinned',
    'recording',
    'appearance',
    'player_guide',
    'source_focused',
    'auto_refresh',
    'wide_rail',
  ];
  for (final scene in reverse ? scenes.reversed : scenes) {
    testWidgets('ORIGINAL golden $scene ready focus and dimensions', (t) async {
      await t.runAsync(() async {
        for (final family in ['Inter', 'Poppins', 'JetBrainsMono']) {
          await (FontLoader(family)
                ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf')))
              .load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      await twoPaneCase(t, (f) async {
        f.playlists = [twoPaneSource('a'), twoPaneSource('b')];
        f.defaultId = 'a';
        f.addMethod = 1;
        f.startupEnabled = true;
        f.startupMode = StartupIptvStorage.startupIptvModePinned;
        final size = scene == 'wide_rail'
            ? const Size(1440, 900)
            : const Size(1280, 800);
        await f.mount(t, size: size);
        final app = t.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.debugShowCheckedModeBanner, isFalse);
        expect(app.theme!.textTheme.bodyMedium!.fontFamily, 'Inter');
        final destination = switch (scene) {
          'add_file' => 'Add a source',
          'channel_lists' => 'Channel lists',
          'startup_pinned' => 'Startup channel',
          'recording' => 'Recording',
          'appearance' => 'Appearance',
          'player_guide' => 'Player guide',
          'auto_refresh' => 'Auto-refresh',
          _ => 'Source a',
        };
        await f.destination(t, destination);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byKey(twoPaneCapture)), size);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          startsWith('iptv-2p-rail-'),
        );
        if (scene == 'add_file') expect(find.text('FILE FORM'), findsOneWidget);
        if (scene == 'source_focused') {
          expect(
            find.text(
              'Not loaded yet. Open this source in IPTV, or refresh it here.',
            ),
            findsOneWidget,
          );
        }
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final path = 'test/goldens/iptv_settings_two_pane/$platform/$scene.png';
        if (Platform.isLinux &&
            !File(path).existsSync() &&
            !captureLinux &&
            !requireLinux) {
          // Step L makes Linux strict after independently captured originals.
          return;
        }
        if (Platform.isLinux && !captureLinux) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Missing ORIGINAL Linux golden',
          );
        }
        await expectLater(
          find.byKey(twoPaneCapture),
          matchesGoldenFile(
            '../../../../goldens/iptv_settings_two_pane/$platform/$scene.png',
          ),
        );
      });
    });
  }
}
