import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/spotlight_board_fixture.dart';

void main() {
  for (final scene in [
    (
      name: 'wide_desktop',
      size: Size(1440, 900),
      dpad: false,
      folder: false,
      look: 'spotlight',
    ),
    (
      name: 'tv_expanded',
      size: Size(1920, 1080),
      dpad: true,
      folder: false,
      look: 'spotlight',
    ),
    (
      name: 'compact_phone',
      size: Size(390, 844),
      dpad: false,
      folder: false,
      look: 'spotlight',
    ),
    (
      name: 'mid_touch',
      size: Size(900, 900),
      dpad: false,
      folder: false,
      look: 'spotlight',
    ),
    (
      name: 'collection',
      size: Size(1440, 900),
      dpad: true,
      folder: true,
      look: 'spotlight',
    ),
    (
      name: 'console',
      size: Size(1440, 900),
      dpad: false,
      folder: false,
      look: 'console',
    ),
  ]) {
    testWidgets('original pixel golden ${scene.name}', (tester) async {
      for (final (family, asset) in [
        ('Inter', 'assets/fonts/Inter-Regular.ttf'),
        ('JetBrainsMono', 'assets/fonts/JetBrainsMono-Regular.ttf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        final loader = FontLoader(family)..addFont(rootBundle.load(asset));
        await loader.load();
      }
      await spotlightCase(tester, (f) async {
        f.dpad = scene.dpad;
        f.look = scene.look;
        f.trailers = false;
        f.animations = false;
        f.shelvesOnly = scene.folder;
        f.paintBackground = !scene.folder;
        f.largeInteractions = !scene.dpad;
        f.sections = [f.shelf('a', metadata: true), f.shelf('b')];
        await f.mount(tester, size: scene.size);
        if (scene.dpad) {
          await f.focus(tester, f.sections.first.nodes[1]);
        }
        await f.settleSetup(tester);
        expect(tester.takeException(), isNull);
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final relative =
            '../../../../goldens/spotlight_board/$platform/${scene.name}.png';
        final file = File(
          'test/goldens/spotlight_board/$platform/${scene.name}.png',
        );
        if (Platform.isLinux) {
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing ORIGINAL Linux golden',
          );
        }
        await expectLater(
          find.byKey(spotlightCapture),
          matchesGoldenFile(relative),
        );
      });
    });
  }
}
