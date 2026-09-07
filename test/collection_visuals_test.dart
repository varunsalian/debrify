import 'support/image_cache_widget_test.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/screens/collections/collection_editor_screen.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/collections/collection_focus_art.dart';
import 'package:debrify/widgets/collections/folder_hero_band.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('COLLECTION_SCREENSHOTS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/debrify-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  Future<void> loadFonts() async {
    for (final (family, asset) in [
      ('Inter', 'assets/fonts/Inter-Regular.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final font = FontLoader(family)..addFont(rootBundle.load(asset));
      await font.load();
    }
  }

  testWidgetsWithImageCache('mixed Spotlight folder shapes retain emoji covers', (
    tester,
  ) async {
    await loadFonts();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final nodes = List.generate(3, (_) => FocusNode());
    final hero = FocusNode();
    addTearDown(() {
      for (final node in [...nodes, hero]) {
        node.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: AppThemeScope(
            theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
            child: Scaffold(
              body: SpotlightBoard(
                hero: const [],
                heroNode: hero,
                heroAddon: null,
                onHeroOpen: (_, __) {},
                trailersEnabled: false,
                sections: [
                  SpotlightShelf(
                    title: 'My collections',
                    nodes: nodes,
                    items: [
                      SpotlightCard(
                        title: 'Movies',
                        coverEmoji: '🎬',
                        shape: SpotlightCardShape.wide,
                        onOpen: () {},
                      ),
                      SpotlightCard(
                        title: 'Favorites',
                        coverEmoji: '⭐',
                        shape: SpotlightCardShape.square,
                        onOpen: () {},
                      ),
                      SpotlightCard(
                        title: 'Series',
                        coverEmoji: '📺',
                        shape: SpotlightCardShape.poster,
                        onOpen: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nodes.first.requestFocus();
    await tester.pumpAndSettle();
    for (final emoji in ['🎬', '⭐', '📺']) {
      expect(find.text(emoji), findsOneWidget);
    }
    for (final (emoji, aspect) in [('🎬', 16 / 9), ('⭐', 1.0), ('📺', 2 / 3)]) {
      final clip = find
          .ancestor(of: find.text(emoji), matching: find.byType(ClipRRect))
          .first;
      final size = tester.getSize(clip);
      expect(size.width / size.height, closeTo(aspect, 0.001));
    }
    expect(tester.takeException(), isNull);
    await capture(tester, 'collection-shapes');
  });

  testWidgetsWithImageCache('phone editor renders imported visual settings', (tester) async {
    await loadFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: CollectionEditorScreen(
            addons: const [],
            collection: const HomeCollection(
              id: 'my',
              title: 'My collections',
              viewMode: 'TABBED_GRID',
              folders: [
                HomeCollectionFolder(
                  id: 'movies',
                  title: 'Movies',
                  coverEmoji: '🎬',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tabs'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'collection-editor');
  });

  testWidgetsWithImageCache(
    'folder hero uses collection backdrop and accepts background video',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
          ),
          home: MediaQuery(
            data: MediaQueryData(size: Size(800, 600), disableAnimations: true),
            child: Scaffold(
              body: FolderHeroBand(
                collectionBackdropUrl: 'https://example.invalid/collection.jpg',
                folder: HomeCollectionFolder(
                  id: 'f',
                  title: 'Movies',
                  coverImageUrl: 'https://example.invalid/cover.jpg',
                  heroVideoUrl: 'https://example.invalid/hero.mp4',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        'https://example.invalid/collection.jpg',
      );
      expect(
        tester
            .widget<CollectionFocusArt>(find.byType(CollectionFocusArt))
            .videoUrl,
        'https://example.invalid/hero.mp4',
      );
      expect(find.text('Movies'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
