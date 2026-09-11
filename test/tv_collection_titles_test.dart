import 'package:debrify/screens/settings/tv_collection_list_style_page.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/collections/tv_collection_titles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'collection style defaults to Filmstrip and rejects unknown values',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getTvCollectionListStyle(), 'filmstrip');
      for (final style in ['grid', 'gallery', 'filmstrip', 'journal']) {
        await StorageService.setTvCollectionListStyle(style);
        expect(await StorageService.getTvCollectionListStyle(), style);
      }
      await StorageService.setTvCollectionListStyle('unknown');
      expect(await StorageService.getTvCollectionListStyle(), 'filmstrip');
    },
  );
  for (final layout in ['gallery', 'filmstrip', 'journal']) {
    for (final activate in [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.space,
    ]) {
      testWidgets(
        '$layout ${activate.keyLabel} distinguishes tap, hold and cancelled hold',
        (tester) async {
          final key = GlobalKey<TvCollectionTitlesState>();
          var opens = 0, plays = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TvCollectionTitles(
                  key: key,
                  style: layout,
                  items: List.generate(
                    6,
                    (i) =>
                        StremioMeta(id: '$i', name: 'Title $i', type: 'movie'),
                  ),
                  onOpen: (_) => opens++,
                  onQuickPlay: (_) => plays++,
                  onLoadMore: () {},
                  onExitTop: () {},
                  exhausted: true,
                ),
              ),
            ),
          );
          key.currentState!.focusFirst();
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(activate);
          await tester.pump(const Duration(milliseconds: 100));
          expect(opens, 0);
          await tester.sendKeyUpEvent(activate);
          expect(opens, 1);
          await tester.sendKeyDownEvent(activate);
          await tester.pump(const Duration(milliseconds: 799));
          expect(plays, 0);
          await tester.pump(const Duration(milliseconds: 1));
          expect(plays, 1);
          await tester.sendKeyRepeatEvent(activate);
          await tester.pump(const Duration(milliseconds: 900));
          await tester.sendKeyUpEvent(activate);
          expect(plays, 1);
          expect(opens, 1);
          await tester.sendKeyDownEvent(activate);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 850));
          await tester.sendKeyUpEvent(activate);
          expect(plays, 1);
          expect(opens, 1);
          await tester.sendKeyDownEvent(activate);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 850));
          await tester.sendKeyUpEvent(activate);
          expect(plays, 1);
        },
      );
    }
  }
  testWidgets('picker saves style and keeps remote focus', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tv_collection_list_style': 'grid',
    });
    await tester.pumpWidget(
      const MaterialApp(home: TvCollectionListStylePage()),
    );
    await tester.pumpAndSettle();
    for (final expected in ['gallery', 'filmstrip']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await StorageService.getTvCollectionListStyle(), expected);
    }
  });

  for (final style in ['gallery', 'filmstrip', 'journal']) {
    testWidgets('$style traverses long lists, pages and returns to filters', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<TvCollectionTitlesState>();
      final items = List.generate(
        40,
        (i) => StremioMeta(
          id: '$i',
          type: 'movie',
          name: 'Title $i',
          description: 'A story without artwork.',
        ),
      );
      var focused = -1, loads = 0, exits = 0;
      StremioMeta? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvCollectionTitles(
              key: key,
              style: style,
              items: items,
              onOpen: (item) {
                opened = item;
                Navigator.of(key.currentContext!).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Details')),
                  ),
                );
              },
              onItemFocused: (item) => focused = int.parse(item.id),
              onLoadMore: () => loads++,
              onExitTop: () => exits++,
            ),
          ),
        ),
      );
      key.currentState!.focusFirst();
      await tester.pumpAndSettle();
      expect(focused, 0);
      for (var i = 0; i < (style == 'gallery' ? 13 : 39); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(focused, 39);
      expect(loads, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened?.id, '39');
      Navigator.of(key.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(focused, 39);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focused, style == 'gallery' ? 36 : 38);
      key.currentState!.focusFirst();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
