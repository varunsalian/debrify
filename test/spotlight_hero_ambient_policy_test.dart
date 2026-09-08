import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets(
      'hero clears forbidden artwork and republishes after reset compact=$compact',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = compact
            ? const Size(390, 844)
            : const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final node = FocusNode();
        addTearDown(node.dispose);
        final ambient = <String?>[];
        StremioMeta? opened;
        const original = StremioMeta(
          id: 'unmapped-custom-title',
          type: 'movie',
          name: 'Title',
          background: 'https://example.invalid/original.jpg',
          poster: 'https://example.invalid/poster.jpg',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: Scaffold(
                body: SpotlightBoard(
                  hero: const [original],
                  sections: const [],
                  heroNode: node,
                  heroAddon: StremioAddon(
                    id: 'test',
                    name: 'Test',
                    manifestUrl: '',
                    baseUrl: '',
                  ),
                  onHeroOpen: (item, _) => opened = item,
                  onAmbient: (art, _) => ambient.add(art),
                  dpad: !compact,
                  trailersEnabled: false,
                ),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        await MetadataPreferencesService.save(
          MetadataPreferences(
            providers: {MetadataCategory.backgrounds: 'tmdb'},
          ),
        );
        await settle();
        expect(ambient, isNotEmpty);
        expect(ambient.last, isNull);
        if (compact) {
          await tester.tap(find.text('Title').first);
        } else {
          node.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        }
        expect(
          opened,
          same(original),
          reason: 'Details must receive the catalog baseline, not presentation',
        );

        final urls = tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((image) => image.imageUrl);
        expect(urls, isNot(contains(original.background)));
        expect(urls, isNot(contains(original.poster)));
        await MetadataPreferencesService.save(MetadataPreferences());
        await settle();
        expect(ambient.last, original.background);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
