import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const watched = StremioMeta(
    id: 'tt1234567',
    imdbId: 'tt1234567',
    type: 'movie',
    name: 'Finished recommendation',
  );
  const fresh = StremioMeta(
    id: 'tt7654321',
    imdbId: 'tt7654321',
    type: 'movie',
    name: 'Fresh recommendation',
    description: 'Original playback metadata',
  );
  const native = StremioMeta(
    id: 'tmdb:42',
    type: 'movie',
    name: 'Unresolved native recommendation',
  );
  const item = StremioMeta(id: 'test-title', type: 'movie', name: 'Detail');

  for (final merged in [false, true]) {
    for (final hide in [false, true]) {
      for (final batches in [false, true]) {
        testWidgets(
          '${merged ? 'merged' : 'catalog'} recommendations hide=$hide batches=$batches',
          (tester) async {
            tester.view.physicalSize = const Size(1280, 2400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.runAsync(() async {
              SharedPreferences.setMockInitialValues({
                HideWatchedPrefs.key: hide,
                'finished_movies_v1': ['tt1234567'],
              });
              HideWatchedPrefs.debugReset();
              await HideWatchedPrefs.warmUp();
              WatchedStatusService.instance.resetProfileScope();
              WatchedStatusService.instance.ensureStarted();
              await WatchedStatusService.instance.firstSnapshot;
            });
            addTearDown(() {
              HideWatchedPrefs.debugReset();
              WatchedStatusService.instance.resetProfileScope();
            });
            expect(
              WatchedStatusService.instance.isWatchedForTicks(
                watched.id,
                'movie',
              ),
              isTrue,
            );
            await StorageService.setDetailPageStyle('marquee');
            // A missing selected artwork provider still publishes new presentation
            // objects. Exercise that real batch path without network credentials.
            await MetadataPreferencesService.save(
              MetadataPreferences(
                features: {},
                providers: {
                  if (batches)
                    MetadataCategory.posters: MetadataPreferences.tmdb,
                  MetadataCategory.credits: MetadataPreferences.current,
                },
                fallback: true,
              ),
            );
            StremioMeta? opened;
            Future<List<StremioMeta>> load() async => [watched, fresh, native];
            final screen = merged
                ? MergedDetailScreen(
                    item: item,
                    addon: StremioAddon(
                      id: 'test',
                      name: 'Test',
                      manifestUrl: '',
                      baseUrl: '',
                    ),
                    isTelevision: true,
                    onResume: (_) async {},
                    recommendationsLoader: load,
                    onRecommendationTap: (value) => opened = value,
                  )
                : CatalogItemDetailScreen(
                    item: item,
                    isTelevision: true,
                    onPlay: () {},
                    onBrowse: () {},
                    recommendationsLoader: load,
                    onRecommendationTap: (value) => opened = value,
                  );
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) =>
                    AppThemeScope(theme: AppThemes.legacy, child: child!),
                home: screen,
              ),
            );
            for (var frame = 0; frame < 20; frame++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(find.text(watched.name), hide ? findsNothing : findsWidgets);
            expect(find.text(fresh.name), findsWidgets);
            expect(find.text(native.name), findsWidgets);
            final freshLabel = find.text(fresh.name).first;
            await tester.ensureVisible(freshLabel);
            if (merged) {
              final card = find
                  .ancestor(of: freshLabel, matching: find.byType(SizedBox))
                  .first;
              await tester.tap(
                find.descendant(of: card, matching: find.byType(InkWell)).first,
              );
            } else {
              await tester.tap(freshLabel);
            }
            await tester.pump();
            // Presentation must never replace the original item used to open
            // playback, including after a hidden first row shifts the indices.
            expect(opened, same(fresh));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
          },
        );
      }
    }
  }
}
