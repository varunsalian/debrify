import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';
import '../../../../support/episodes_panel_source.dart';

const _captureLinux = bool.fromEnvironment(
  'EPISODES_PANEL_CAPTURE_ORIGINAL_LINUX',
);
const _requireLinux = bool.fromEnvironment(
  'EPISODES_PANEL_REQUIRE_ORIGINAL_LINUX',
);
const _reverse = bool.fromEnvironment('EPISODES_PANEL_REVERSE_GOLDENS');

void main() {
  final scenes = [
    'classic_phone',
    'classic_tv',
    'compact',
    'unavailable_tv',
    'options_tv',
  ];
  final ordered = _reverse ? scenes.reversed : scenes;
  for (final scene in ordered) {
    testWidgets(
      'ORIGINAL golden $scene dimensions focus no art and exact requests',
      (t) async {
        await episodesPanelCase(t, 'golden-$scene', 400 + scenes.indexOf(scene), (
          f,
        ) async {
          f.custom = false;
          f.television = scene.endsWith('_tv');
          f.compact = scene == 'compact' || scene == 'options_tv';
          f.chrome = !f.compact;
          f.failMeta = scene == 'unavailable_tv';
          final size = scene == 'classic_phone'
              ? const Size(390, 844)
              : scene == 'compact'
              ? const Size(900, 1200)
              : const Size(1920, 1080);
          if (scene.startsWith('classic_')) {
            await f.mountScreen(t, size: size);
          } else {
            await f.mount(t, size: size);
          }
          if (f.failMeta) {
            expect(find.text("Couldn't load episodes"), findsOneWidget);
            expect(
              FocusManager.instance.primaryFocus!.debugLabel,
              'catalog-ep-retry',
            );
          } else {
            expect(find.textContaining('Pilot'), findsWidgets);
            expect(find.text('Season 1'), findsOneWidget);
            if (scene == 'options_tv') {
              await t.longPress(find.textContaining('Pilot').first);
              await t.pump();
              await t.pump(const Duration(milliseconds: 400));
              expect(find.text('Play'), findsOneWidget);
              expect(
                find.descendant(
                  of: find.byWidget(
                    FocusManager.instance.primaryFocus!.context!.widget,
                  ),
                  matching: find.text('Play'),
                ),
                findsOneWidget,
              );
            } else if (f.television) {
              expect(
                FocusManager.instance.primaryFocus!.debugLabel,
                'catalog-ep-0',
              );
            } else {
              final focus =
                  FocusManager.instance.primaryFocus?.debugLabel ?? '';
              expect(
                focus.startsWith('catalog-ep-') ||
                    focus == 'catalog-select-source-btn',
                isFalse,
              );
            }
          }
          expect(t.view.physicalSize, size);
          expect(t.view.devicePixelRatio, 1);
          expect(f.show.poster, isNull);
          expect(f.show.background, isNull);
          expect(f.videos.every((v) => v['thumbnail'] == null), isTrue);
          expect(
            t
                .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
                .map((w) => w.imageUrl),
            isEmpty,
          );
          final requests = f.requests.map(f.requestIdentity).toList()..sort();
          final expected = [
            'GET episodes-original.invalid/meta/series/${f.id}.json',
            if (f.failMeta)
              'GET api.trakt.tv/shows/${f.id}/seasons?extended=episodes,full',
            if (f.failMeta)
              'GET episodes-original.invalid/meta/series/${f.id}.json',
            if (!f.failMeta) 'GET api.tvmaze.com/shows/1',
            if (!f.failMeta) 'GET api.tvmaze.com/lookup/shows?imdb=${f.id}',
          ]..sort();
          expect(requests, expected);
          // The bounded fixture pumps 20 × 50 ms after the ready predicate;
          // options adds exactly 400 ms. Capture never waits on image/network art.
          await t.pump();
          final platform = Platform.isLinux ? 'linux' : 'macos';
          final path = 'test/goldens/episodes_panel/$platform/$scene.png';
          final strict =
              !Platform.isLinux ||
              _captureLinux ||
              _requireLinux ||
              File(path).existsSync() ||
              (episodesCheckerConfig()['completed_step'] as int) >= 6;
          if (strict) {
            await expectLater(
              find.byKey(const ValueKey('episodes-application-canvas')),
              matchesGoldenFile(
                '../../../../goldens/episodes_panel/$platform/$scene.png',
              ),
            );
          }
        });
      },
    );
  }
}
