import 'package:debrify/services/main_page_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalHttp extends HttpOverrides {}

void main() {
  testWidgets(
    'episode presentation and reset preserve current focus and scroll',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const show = StremioMeta(
        id: 'custom-focus-show',
        type: 'series',
        name: 'Show',
      );
      late StremioAddon addon;
      // Warm the real addon episode cache, then let the mounted panel use it.
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            request.response.write(
              jsonEncode({
                'meta': {
                  'videos': [
                    for (var i = 1; i <= 20; i++)
                      {
                        'season': 1,
                        'episode': i,
                        'title': 'Episode $i',
                        'thumbnail': 'catalog-still',
                        'overview': 'Catalog plot',
                      },
                  ],
                },
              }),
            );
            await request.response.close();
          });
          final base = 'http://127.0.0.1:${server.port}';
          addon = StremioAddon(
            id: 'focus-test',
            name: 'Test',
            baseUrl: base,
            manifestUrl: '$base/manifest.json',
            resources: const ['meta'],
            types: const ['series'],
          );
          try {
            final rows = await StremioService.instance.fetchSeriesMeta(
              addon,
              show.id,
            );
            expect(rows, hasLength(20));
          } finally {
            await server.close(force: true);
          }
        }, _LocalHttp()),
      );
      final nodes = DetailCellNodes('regression');
      final scroll = ScrollController();
      EpisodesPanelView? snapshot;
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: Scaffold(
              body: EpisodesPanel(
                show: show,
                addon: addon,
                isTelevision: true,
                contentBuilder: (context, view) {
                  snapshot = view;
                  return ListView(
                    controller: scroll,
                    children: [
                      for (final episode in view.episodes)
                        Focus(
                          focusNode: nodes.of(
                            view.generation,
                            episode.season,
                            episode.number,
                          ),
                          child: SizedBox(
                            height: 100,
                            child: Text(episode.title),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(snapshot!.episodes, hasLength(20));
      final generation = snapshot!.generation;
      scroll.jumpTo(600);
      await tester.pump();
      final focused = nodes.of(generation, 1, 8);
      focused.requestFocus();
      await tester.pump();
      expect(focused.hasFocus, true);
      for (final selected in [true, false, true]) {
        await MetadataPreferencesService.save(
          MetadataPreferences(
            providers: selected
                ? {MetadataCategory.episodeArtwork: 'tmdb'}
                : {},
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(snapshot!.generation, generation);
        expect(focused.hasFocus, true);
        expect(scroll.offset, 600);
        expect(
          snapshot!.episodes[7].thumbnailUrl,
          selected ? null : 'catalog-still',
        );
      }
      final presentedEpisodes = snapshot!.episodes;
      MainPageBridge.notifyHomeSettingsChanged();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(snapshot!.episodes, same(presentedEpisodes));
      expect(focused.hasFocus, true);
      expect(scroll.offset, 600);
      await tester.pumpWidget(const SizedBox());
      nodes.dispose();
      scroll.dispose();
    },
  );
}
