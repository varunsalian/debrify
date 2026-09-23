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
import 'package:debrify/widgets/collections/collection_category_tabs.dart';
import 'package:debrify/widgets/collections/collection_list_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final (width, television, direct, style) in [
    (720.0, true, false, 'spotlight'),
    (1280.0, true, false, 'spotlight'),
    (390.0, false, false, 'spotlight'),
    (1280.0, false, false, 'spotlight'),
    (390.0, false, true, 'spotlight'),
    (1280.0, true, true, 'spotlight'),
    (1280.0, true, false, 'grid'),
    (1280.0, false, false, 'grid'),
    (1280.0, true, false, 'gallery'),
    (1280.0, false, false, 'gallery'),
  ]) {
    testWidgets(
      'collection at $width television=$television direct=$direct style=$style defaults and navigates correctly',
      (tester) async {
        debugDefaultTargetPlatformOverride = !television && width >= 600
            ? TargetPlatform.macOS
            : TargetPlatform.android;
        try {
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
            'tv_collection_list_style': style,
            HomeCollectionsStore.folderLayoutKey: 'rows',
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
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamily: 'Inter',
              ),
              home: RepaintBoundary(
                key: boundary,
                child: CollectionFolderScreen(
                  collection: collection,
                  isTelevision: television,
                  fromHome: true,
                  sourceKey: direct
                      ? collection.folders.first.sources.first.key
                      : null,
                  onOpenItem: (_) {},
                ),
              ),
            ),
          );
          await settle();
          Finder chip(String label) => find.byWidgetPredicate(
            (w) => w is StremioDropdown && w.label == label,
          );
          if (style != 'spotlight') {
            final view = tester.widget<StremioDropdown>(chip('View'));
            expect(view.options.first.label, 'All');
            expect(
              view.value,
              view.options
                  .firstWhere((option) => option.label == 'Gallery')
                  .value,
            );
            expect(find.byType(CollectionListGallery), findsOneWidget);
            if (television) {
              tester
                  .widget<StremioDropdown>(chip('Folder'))
                  .focusNode!
                  .requestFocus();
              await settle();
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
              await settle();
              expect(view.focusNode!.hasFocus, isTrue);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              await tester.tap(chip('View'));
            }
            await settle();
            await tester.tap(find.text('Gallery').last);
            await settle();
            expect(find.byType(CollectionListGallery), findsOneWidget);
            expect(chip('View'), findsOneWidget);
            // All remains reachable after switching back to Gallery.
            await tester.tap(chip('View'));
            await settle();
            await tester.tap(find.text('All').last);
            await settle();
            expect(find.byType(CollectionListGallery), findsNothing);
            await tester.tap(chip('View'));
            await settle();
            await tester.tap(find.text('Gallery').last);
            await settle();
            tester
                .widget<CollectionListGallery>(
                  find.byType(CollectionListGallery),
                )
                .onOpen(0);
            await settle();
            expect(
              tester
                  .widget<CollectionFolderScreen>(
                    find.byType(CollectionFolderScreen).last,
                  )
                  .sourceKey,
              collection.folders.first.sources.first.key,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await settle();
            return;
          }
          if (direct) {
            expect(find.text('All titles'), findsNothing);
            expect(find.byType(CollectionCategoryTabs), findsNothing);
            expect(chip('List'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await settle();
            return;
          }
          if (width < 600) {
            final tabs = tester.widget<CollectionCategoryTabs>(
              find.byType(CollectionCategoryTabs),
            );
            expect(tabs.labels, ['All', 'New Movies', 'New Series']);
            expect(tabs.selectedIndex, 0);
            await tester.tap(find.text('New Series'));
            await settle();
            expect(
              tester
                  .widget<CollectionCategoryTabs>(
                    find.byType(CollectionCategoryTabs),
                  )
                  .selectedIndex,
              2,
            );
            await tester.tap(find.text('All'));
            await settle();
            expect(
              tester
                  .widget<CollectionCategoryTabs>(
                    find.byType(CollectionCategoryTabs),
                  )
                  .selectedIndex,
              0,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await settle();
            return;
          }
          final list = tester.widget<StremioDropdown<int>>(chip('List'));
          expect(list.options.first.label, 'All');
          expect(list.value, list.options[1].value);
          list.onSelected(list.options.first.value);
          await settle();
          expect(
            tester.widget<StremioDropdown<int>>(chip('List')).value,
            list.options.first.value,
          );
          // Selecting a concrete list still maps to its original rail index.
          list.onSelected(list.options[1].value);
          await settle();
          expect(tester.widget<StremioDropdown>(chip('List')).value, 0);
          if (!television) {
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await settle();
            return;
          }
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
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
