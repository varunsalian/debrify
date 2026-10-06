import 'dart:io';

import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/stremio_tv_goldens.dart';
import '../../../../support/stremio_tv_preferences.dart';

const _reverse = bool.fromEnvironment('STREMIO_TV_REVERSE_GOLDENS');

Future<void> fonts(WidgetTester t) async {
  await t.runAsync(() async {
    for (final family in ['Roboto', 'Inter', 'Poppins', 'JetBrainsMono']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      if (family == 'JetBrainsMono') {
        loader.addFont(rootBundle.load('assets/fonts/$family-Bold.ttf'));
      }
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}

void main() {
  final scenes = [
    'loading_tv',
    'empty_header_tv',
    'search_phone',
    'empty_desktop',
    'import_menu_tv',
    'picker_region_tv',
  ];
  for (final scene in _reverse ? scenes.reversed : scenes) {
    testWidgets(
      'ORIGINAL golden $scene readiness dimensions and tuner exclusion',
      (t) async {
        await fonts(t);
        await stremioTvCase(t, (f) async {
          f.count = scene == 'picker_region_tv' ? 1 : 0;
          f.television = scene.endsWith('_tv');
          final size = scene == 'search_phone'
              ? const Size(390, 844)
              : scene == 'empty_desktop'
              ? const Size(1280, 800)
              : const Size(1920, 1080);
          if (scene == 'empty_header_tv') {
            await t.runAsync(() => f.provider('torbox'));
          }
          if (scene == 'empty_desktop') {
            await t.runAsync(RealDebridStorage.deleteApiKey);
          }
          if (scene == 'import_menu_tv') {
            await t.runAsync(
              () => MdblistStorage.saveMdblistApiKey('original-mdblist'),
            );
          }
          StremioTvHeldPreferences? held;
          if (scene == 'loading_tv') {
            await t.runAsync(f.seed);
            held = await t.runAsync(StremioTvHeldPreferences.install);
          }
          try {
            if (scene == 'picker_region_tv') {
              f.rdFails = true;
              f.headValid = false;
              f.streams.insert(0, {
                'name': 'Direct fixture',
                'title': 'Original.Direct.1080p.mkv',
                'url': 'https://direct.test/original.mp4',
                'behaviorHints': {'videoSize': 100000000},
              });
            }
            await f.mount(
              t,
              size: size,
              wait: held == null,
              seedChannels: held == null,
            );
            expect(t.view.physicalSize, size);
            expect(t.view.devicePixelRatio, 1);
            expect(
              MediaQuery.textScalerOf(f.hostKey.currentContext!).scale(1),
              1,
            );
            if (held != null) {
              await f.until(t, () => held!.ready.isCompleted);
              await f.settle(t);
              expect(find.text('No Catalog Addons'), findsNothing);
            } else if (scene == 'empty_header_tv') {
              f.node('searchBtn').requestFocus();
              await f.settle(t);
              expect(f.node('searchBtn').hasFocus, isTrue);
              expect(find.text('TB'), findsOneWidget);
            } else if (scene == 'search_phone') {
              f.node('searchBtn').requestFocus();
              await t.pump();
              await f.key(t, LogicalKeyboardKey.enter);
              await t.enterText(find.byType(EditableText), 'Original');
              await f.settle(t);
              expect(
                t
                    .widget<EditableText>(find.byType(EditableText))
                    .controller
                    .text,
                'Original',
              );
              expect(
                t
                    .widget<EditableText>(find.byType(EditableText))
                    .focusNode
                    .hasFocus,
                isTrue,
              );
            } else if (scene == 'import_menu_tv') {
              await f.menu(t);
              f.node('localCatalogs').requestFocus();
              await f.key(t, LogicalKeyboardKey.arrowRight);
              await f.settle(t);
              expect(find.text('From MDBList'), findsOneWidget);
              expect(find.text('Manage'), findsOneWidget);
              expect(FocusManager.instance.primaryFocus, isNotNull);
            } else if (scene == 'picker_region_tv') {
              await f.play(t);
              expect(find.text('All (3)'), findsOneWidget);
              expect(find.text('Direct (1)'), findsOneWidget);
              expect(find.text('Torrent (2)'), findsOneWidget);
              final items = find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_SourcePickerItem',
              );
              await f.tap(t, find.text('Direct (1)'));
              await f.tap(t, items.first);
              await f.until(
                t,
                () => find.byIcon(Icons.error_outline).evaluate().isNotEmpty,
              );
              await f.tap(t, find.text('All (3)'));
              await f.settle(t);
              expect(find.byIcon(Icons.error_outline), findsOneWidget);
              final firstFocus = t
                  .widget<Focus>(
                    find
                        .descendant(
                          of: items.first,
                          matching: find.byType(Focus),
                        )
                        .first,
                  )
                  .focusNode;
              expect(FocusManager.instance.primaryFocus, same(firstFocus));
              expect(find.byType(Image), findsNothing);
              final image = await t.runAsync(() => stremioTvPickerImage(t));
              final platform = Platform.isLinux ? 'linux' : 'macos';
              try {
                await expectLater(
                  image!,
                  matchesGoldenFile(
                    '../../../../goldens/stremio_tv/$platform/$scene.png',
                  ),
                );
              } finally {
                image?.dispose();
              }
              return;
            } else {
              FocusManager.instance.primaryFocus?.unfocus();
              await f.settle(t);
            }
            if (held == null) {
              expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
            } else {
              expect(find.byType(CircularProgressIndicator), findsNothing);
              expect(find.byType(ListView), findsOneWidget);
            }
            expect(find.byType(StremioTvTuner), findsNothing);
            expect(find.byType(Image), findsNothing);
            expect(t.view.physicalSize, size);
            expect(t.view.devicePixelRatio, 1);
            expect(
              MediaQuery.textScalerOf(f.hostKey.currentContext!).scale(1),
              1,
            );
            if (held == null) {
              expect(find.text('No Catalog Addons'), findsOneWidget);
            }
            final platform = Platform.isLinux ? 'linux' : 'macos';
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../../../../goldens/stremio_tv/$platform/$scene.png',
              ),
            );
          } finally {
            if (held != null && !held.release.isCompleted) {
              held.release.complete();
              await f.settle(t);
            }
          }
        });
      },
    );
  }
}
