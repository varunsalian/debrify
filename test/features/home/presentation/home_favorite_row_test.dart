import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:debrify/features/home/presentation/home_favorite_cell.dart';
import 'package:debrify/features/home/presentation/home_favorite_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets(
      'favourites row preserves lazy cards, focus and scroll across caption/theme changes: TV=$television',
      (tester) async {
        final nodes = List.generate(100, (_) => FocusNode());
        addTearDown(() {
          for (final node in nodes) {
            node.dispose();
          }
        });
        final built = <int>{};
        final opened = <int>[];
        var captionBand = 36.0;
        var dark = false;
        Widget page() => MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => buildHomeFavoriteRow(
                context,
                isTelevision: television,
                posterWidth: 160,
                captionBand: captionBand,
                title:
                    'Favourites with a long title that must stay on one line',
                tags: const [Text('Channels'), Text('Favorites')],
                itemCount: nodes.length,
                cellBuilder: (index, width, height) {
                  built.add(index);
                  expect(width, 160);
                  expect(height, 240 + captionBand);
                  return HomeFavoriteCell(
                    isTelevision: television,
                    column: index,
                    rowNodes: nodes,
                    onLeftEdge: () {},
                    onUp: () {},
                    onDown: () {},
                    child: InkWell(
                      key: ValueKey('card-$index'),
                      focusNode: nodes[index],
                      onTap: () => opened.add(index),
                      child: Text('Card $index'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpWidget(page());
        expect(tester.getSize(find.byType(ListView)).height, 290);
        expect(
          tester.getSize(find.byKey(const ValueKey('card-0'))),
          const Size(160, 276),
        );
        expect(built.length, lessThan(100));
        expect(built, isNot(contains(50)));
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.clipBehavior, Clip.hardEdge);
        expect(list.scrollCacheExtent, const ScrollCacheExtent.pixels(400));
        final title = tester.widget<Text>(
          find.text('Favourites with a long title that must stay on one line'),
        );
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(title.style!.fontSize, television ? 20 : 19);
        expect(
          tester.getTopLeft(find.text('Channels')).dx,
          lessThan(tester.getTopLeft(find.text('Favorites')).dx),
        );
        await tester.tap(find.byKey(const ValueKey('card-0')));
        expect(opened, [0]);
        nodes[0].requestFocus();
        await tester.pump();
        if (television) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        } else {
          nodes[1].requestFocus();
        }
        await tester.pump();
        expect(nodes[1].hasFocus, isTrue);
        final card = tester.element(find.byKey(const ValueKey('card-1')));
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable),
        );
        final scroll = scrollable.position;
        await tester.drag(find.byType(ListView), const Offset(-200, 0));
        await tester.pumpAndSettle();
        final offset = scroll.pixels;
        expect(offset, greaterThan(0));
        captionBand = 0;
        dark = true;
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(ListView)).height, 254);
        expect(
          tester.element(find.byKey(const ValueKey('card-1'))),
          same(card),
        );
        expect(
          tester.state<ScrollableState>(find.byType(Scrollable)),
          same(scrollable),
        );
        // Theme changes may recreate ScrollPosition through ScrollBehavior;
        // the row's element, offset and focused card must remain intact.
        expect(scrollable.position.pixels, offset);
        expect(nodes[1].hasFocus, isTrue);
        expect(opened, [0]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        // Nodes remain caller-owned after the row goes away.
        nodes[1].requestFocus();
      },
    );
  }

  testWidgets(
    'empty favourites retain their header and row space without creating a card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => buildHomeFavoriteRow(
                context,
                isTelevision: false,
                posterWidth: 120,
                captionBand: 40,
                title: 'Empty row',
                tags: const [],
                itemCount: 0,
                cellBuilder: (_, _, _) =>
                    throw StateError('Empty row built a card'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Empty row'), findsOneWidget);
      expect(tester.getSize(find.byType(ListView)).height, 234);
      expect(tester.takeException(), isNull);
    },
  );
}
