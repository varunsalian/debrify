import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:debrify/widgets/movie_watched_badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final merged in [false, true]) {
    testWidgets(
      'recommendation navigation retains original baseline merged=$merged',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await StorageService.setDetailPageStyle('classic');
        await MetadataPreferencesService.save(
          MetadataPreferences(
            providers: {MetadataCategory.information: 'tmdb'},
          ),
        );
        const item = StremioMeta(
          id: 'custom-main',
          type: 'movie',
          name: 'Main',
        );
        const rec = StremioMeta(
          id: 'custom-rec',
          type: 'movie',
          name: 'Recommended',
          description: 'Catalog description',
        );
        StremioMeta? opened;
        final Widget detail = merged
            ? MergedDetailScreen(
                item: item,
                addon: StremioAddon(
                  id: 'test',
                  name: 'Test',
                  manifestUrl: '',
                  baseUrl: '',
                ),
                onResume: (_) async {},
                recommendationsLoader: () async => [rec],
                onRecommendationTap: (m) => opened = m,
              )
            : CatalogItemDetailScreen(
                item: item,
                onPlay: () async {},
                onBrowse: () {},
                recommendationsLoader: () async => [rec],
                onRecommendationTap: (m) => opened = m,
              );
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(theme: AppThemes.legacy, child: detail),
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final tile = merged
            ? find
                  .ancestor(
                    of: find.byWidgetPredicate(
                      (w) => w is MovieWatchedBadge && w.imdbId == rec.id,
                    ),
                    matching: find.byType(InkWell),
                  )
                  .first
            : find.text('Recommended').first;
        await tester.ensureVisible(tile);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(tile);
        await tester.pump();
        expect(opened, same(rec));
        expect(opened?.description, 'Catalog description');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
