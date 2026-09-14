import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final style in ['classic', 'showcase']) {
    testWidgets('source actions retain catalog metadata in $style', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.setDetailPageStyle(style);
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {MetadataCategory.information: 'tmdb'},
          language: 'fr-FR',
        ),
      );
      const original = StremioMeta(
        id: 'unmapped-source-test',
        type: 'movie',
        name: 'Catalog search title',
        description: 'Catalog plot',
      );
      final opened = <StremioMeta>[];
      final counted = <StremioMeta>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: MergedDetailScreen(
              item: original,
              addon: StremioAddon(
                id: 'test',
                name: 'Test',
                manifestUrl: '',
                baseUrl: '',
              ),
              onResume: (_) async {},
              boundSourceCount: (item) {
                counted.add(item);
                return 0;
              },
              onSelectSource: (item) async {
                opened.add(item);
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (style == 'showcase') {
        final model = tester
            .widget<DetailShowcase>(find.byType(DetailShowcase))
            .model;
        // A real provider overlay is active, even though this custom title has
        // no mapping. Actions must never receive this presentation object.
        expect(model.item, isNot(same(original)));
        expect(model.item.description, isNull);
        model.onSelectSource!();
        await tester.pump();
        model.onManageSources!();
        await tester.pump();
        expect(opened, hasLength(2));
      } else {
        final bind = find.text('Bind source');
        await tester.ensureVisible(bind);
        await tester.tap(bind);
        await tester.pump();
        expect(opened, hasLength(1));
      }
      expect(counted, isNotEmpty);
      for (final item in [...opened, ...counted]) {
        expect(item, same(original));
        expect(item.name, 'Catalog search title');
        expect(item.description, 'Catalog plot');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
