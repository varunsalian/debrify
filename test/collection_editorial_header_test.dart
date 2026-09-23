import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [720.0, 1280.0]) {
    testWidgets(
      'editorial collection at $width keeps remote navigation and menus',
      (tester) async {
        final font = FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await font.load();
        await icons.load();
        Future<void> settle() async {
          if (const bool.fromEnvironment('CAPTURE_COLLECTION_UI')) {
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          } else {
            await tester.pumpAndSettle();
          }
        }

        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        StremioService.instance.invalidateCache();
        final addon = StremioAddon(
          id: 'editorial',
          name: 'Cinema',
          manifestUrl: 'https://example.invalid/manifest.json',
          baseUrl: 'https://example.invalid',
          resources: ['catalog'],
          catalogs: const [
            StremioAddonCatalog(id: 'new', type: 'movie', name: 'New Movies'),
            StremioAddonCatalog(
              id: 'series',
              type: 'series',
              name: 'New Series',
            ),
          ],
        );
        final collection = HomeCollection(
          id: 'editorial',
          title: 'Genres',
          folders: [
            HomeCollectionFolder(
              id: 'action',
              title: width < 1000
                  ? 'Action and adventure with a very long folder name'
                  : 'Action',
              sources: const [
                CollectionCatalogSource(
                  addonId: 'editorial',
                  type: 'movie',
                  catalogId: 'new',
                ),
                CollectionCatalogSource(
                  addonId: 'editorial',
                  type: 'series',
                  catalogId: 'series',
                ),
              ],
            ),
          ],
        );
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode([addon.toJson()]),
          HomeCollectionsStore.prefsKey: jsonEncode([collection.toJson()]),
          'tv_collection_list_style': 'spotlight',
          'home_animations_enabled': const bool.fromEnvironment(
            'CAPTURE_COLLECTION_UI',
          ),
          'tv_collection_spotlight_alpha_migrated_v1': true,
        });
        await tester.runAsync(() async {
          await StremioService.instance.getCatalogAddons();
          await http.runWithClient(
            () async {
              for (final catalog in addon.catalogs) {
                await StremioService.instance.fetchCatalog(addon, catalog);
              }
            },
            () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'metas': [
                    for (var i = 0; i < 8; i++)
                      {'id': 'tt$i', 'type': 'movie', 'name': 'Film $i'},
                  ],
                }),
                200,
              ),
            ),
          );
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
            home: RepaintBoundary(
              key: boundary,
              child: CollectionFolderScreen(
                collection: collection,
                isTelevision: true,
                onOpenItem: (_) {},
              ),
            ),
          ),
        );
        await settle();
        Finder chip(String label) => find.byWidgetPredicate(
          (w) => w is StremioDropdown && w.label == label,
        );
        expect(find.text('Collections'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final folder = tester.widget<StremioDropdown>(chip('Folder'));
        folder.focusNode!.requestFocus();
        await settle();
        final rect = tester.getRect(chip('Folder'));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await settle();
        expect(
          tester.widget<StremioDropdown>(chip('List')).focusNode!.hasFocus,
          isTrue,
        );
        expect(tester.getRect(chip('Folder')), rect);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await settle();
        expect(
          tester.widget<StremioDropdown>(chip('Sort')).focusNode!.hasFocus,
          isTrue,
        );
        if (width >= 1000) {
          expect(tester.getRect(chip('Sort')).right, width * (1 - 84 / 1920));
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle();
        await tester.tap(find.text('Title · A → Z'));
        await settle();
        expect(find.text('Title · A → Z'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle();
        final board = tester.widget<SpotlightBoard>(
          find.byType(SpotlightBoard),
        );
        expect(
          board.sections.expand((s) => s.nodes).any((n) => n.hasFocus),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_COLLECTION_UI') &&
            width == 1280) {
          folder.focusNode!.requestFocus();
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/images/home_snowy_mountain.jpg'),
              boundary.currentContext!,
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
          });
          await settle();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/debrify-collection-header.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await settle();
      },
    );
  }
}
