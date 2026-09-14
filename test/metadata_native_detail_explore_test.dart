import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'native detail opens Explore without an IMDb recommendation loader',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.setDetailPageStyle('classic');
      await MetadataPreferencesService.save(
        MetadataPreferences(features: {MetadataFeature.people}),
      );
      const native = StremioMeta(
        id: 'tmdb:550',
        type: 'movie',
        name: 'Native title',
      );
      StremioMeta? opened;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppThemeScope(theme: AppThemes.legacy, child: child!),
          home: MergedDetailScreen(
            item: native,
            addon: StremioAddon(
              id: 'test',
              name: 'Test',
              manifestUrl: '',
              baseUrl: '',
            ),
            onResume: (_) async {},
            // Navigation is available independently of the absent IMDb loader.
            onRecommendationTap: (item) => opened = item,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final explore = find.byIcon(Icons.explore_outlined);
      expect(explore, findsOneWidget);
      await tester.ensureVisible(explore);
      await tester.tap(explore);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final page = tester.widget<MetadataExplorePage>(
        find.byType(MetadataExplorePage),
      );
      expect(page.item.id, native.id);
      const next = StremioMeta(
        id: 'tmdb:551',
        type: 'movie',
        name: 'Next title',
      );
      page.onOpen(next);
      expect(opened, same(next));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
