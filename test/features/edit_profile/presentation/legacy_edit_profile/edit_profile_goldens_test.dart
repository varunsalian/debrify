import 'dart:io';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/edit_profile_fixture.dart';

void main() {
  const reverse = bool.fromEnvironment('EDIT_PROFILE_REVERSE_GOLDENS');
  final scenes = ['phone_create', 'phone_edit', 'tv_profile', 'tv_access'];
  for (final scene in reverse ? scenes.reversed : scenes) {
    testWidgets('R ORIGINAL golden $scene', (t) async {
      await t.runAsync(() async {
        await (FontLoader(
          'Inter',
        )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      await editProfileCase(t, (f) async {
        f.television = scene.startsWith('tv_');
        final target = scene == 'phone_edit' || scene == 'tv_access'
            ? await t.runAsync(() => f.profile('Cinema'))
            : null;
        if (target != null) {
          await t.runAsync(() async {
            await f.engine(f.admin, 'alpha', 'Alpha engine');
            await f.engine(f.admin, 'beta', 'Beta engine');
            final cloud = await f.resource('Cinema cloud');
            await f.grant(target, cloud, {ResourcePermission.use});
            await f.refreshActor();
          });
        }
        await f.mount(
          t,
          target: target,
          size: switch (scene) {
            'phone_create' => const Size(390, 844),
            'phone_edit' => const Size(1100, 1600),
            'tv_profile' => const Size(1280, 720),
            _ => const Size(1920, 1080),
          },
        );
        if (scene == 'tv_access') await f.section(t, 'access');
        if (f.television) {
          final label = scene == 'tv_access'
              ? 'Edit profile access tab'
              : 'Edit profile profile tab';
          final node = FocusManager.instance.rootScope.descendants.singleWhere(
            (n) => n.debugLabel == label,
          );
          node.requestFocus();
          await t.pump();
          expect(node.hasFocus, isTrue);
        } else {
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump();
        }
        for (var i = 0; i < 6; i++) {
          await f.settle(t);
        }
        expect(t.takeException(), isNull);
        expect(
          find.text(
            scene == 'phone_edit' || scene == 'tv_access'
                ? 'Edit profile'
                : 'Create profile',
          ),
          findsOneWidget,
        );
        if (scene == 'tv_access') {
          expect(find.text('Cinema cloud'), findsOneWidget);
        }
        final platform = Platform.isMacOS ? 'macos' : 'linux';
        final path = '../../../../goldens/edit_profile/$platform/$scene.png';
        await expectLater(find.byKey(f.capture), matchesGoldenFile(path));
      });
    });
  }
}
