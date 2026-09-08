import 'package:debrify/models/home_collection.dart';
import 'package:debrify/widgets/collections/collection_browser_hero.dart';
import 'package:debrify/widgets/collections/collection_list_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lists = List.generate(
    49,
    (i) => CollectionListPreview(
      id: '$i',
      title: 'List $i',
      source: 'TRAKT',
      items: const [],
    ),
  );
  for (final size in [
    const Size(360, 740),
    const Size(844, 390),
    const Size(800, 1024),
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('gallery and hero fit $size with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final back = FocusNode();
      addTearDown(back.dispose);
      final opened = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.4),
            ),
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    CollectionBrowserHero(
                      collectionTitle: 'Streaming Services',
                      folder: const HomeCollectionFolder(
                        id: 'f',
                        title: 'Netflix',
                      ),
                      listCount: 49,
                      backNode: back,
                      onDown: () {},
                    ),
                    Expanded(
                      child: CollectionListGallery(
                        lists: lists,
                        onOpen: opened.add,
                        onExitTop: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('List 0'));
      expect(opened, [0]);
      await tester.drag(find.byType(GridView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('remote traverses lazy rows and returns to the selected card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<CollectionListGalleryState>();
    final opened = <int>[];
    var exits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: CollectionListGallery(
              key: key,
              lists: lists,
              onExitTop: () => exits++,
              onOpen: (index) async {
                opened.add(index);
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Opened list')),
                  ),
                );
                key.currentState?.focusIndex(index);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.focusFirst();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(exits, 1);
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_list_30',
    );
    expect(find.text('List 0'), findsNothing);
    final controller = tester
        .widget<GridView>(find.byType(GridView))
        .controller!;
    final offset = controller.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(opened, [30]);
    Navigator.of(tester.element(find.text('Opened list'))).pop();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_list_30',
    );
    expect(controller.offset, offset);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_list_31',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposal cancels pending focus and data arrival preserves focus',
    (tester) async {
      final key = GlobalKey<CollectionListGalleryState>();
      Widget page(bool loading) => MaterialApp(
        home: Scaffold(
          body: CollectionListGallery(
            key: key,
            lists: [
              CollectionListPreview(
                id: 'a',
                title: 'A list',
                source: 'TMDB',
                items: const [],
                loading: loading,
              ),
            ],
            onOpen: (_) {},
            onExitTop: () {},
          ),
        ),
      );
      await tester.pumpWidget(page(true));
      key.currentState!.focusFirst();
      await tester.pumpAndSettle();
      final node = FocusManager.instance.primaryFocus;
      await tester.pumpWidget(page(false));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(node));
      key.currentState!.focusFirst();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
