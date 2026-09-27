import 'package:debrify/features/home/presentation/home_canvas_layout.dart';
import 'package:debrify/features/home/presentation/home_canvas_shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fixed in [false, true]) {
    testWidgets('Canvas shelf preserves lazy sizing with fixed height=$fixed', (
      tester,
    ) async {
      final built = <int>{};
      await tester.pumpWidget(
        _host(
          buildHomeCanvasShelf(
            railKey: 'row',
            itemCount: 100,
            cardWidth: 100,
            cardHeight: fixed ? 160 : null,
            itemBuilder: (_, index) {
              built.add(index);
              return SizedBox(
                key: ValueKey('card-$index'),
                height: 100,
                child: Text('Card $index'),
              );
            },
          ),
        ),
      );
      expect(built.length, greaterThan(3));
      expect(built.length, lessThan(20));
      final card = find.byKey(const ValueKey('card-0'));
      expect(tester.getSize(card), Size(100, fixed ? 160 : 100));
      expect(tester.getTopLeft(card), Offset(55, fixed ? 30 : 60));
      final initial = Set<int>.of(built);
      await tester.drag(find.byType(ListView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(built.difference(initial), isNotEmpty);
      expect(built.length, lessThan(100));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'appending cards retains the rail scroll position and focused node',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget page(int count) => _host(
        buildHomeCanvasShelf(
          railKey: 'stable',
          itemCount: count,
          cardWidth: 100,
          cardHeight: 160,
          itemBuilder: (_, index) => index == 0
              ? Focus(focusNode: node, child: const Text('First'))
              : Text('Card $index'),
        ),
      );
      await tester.pumpWidget(page(20));
      node.requestFocus();
      await tester.pump();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final focusFinder = find.byWidgetPredicate(
        (widget) => widget is Focus && widget.focusNode == node,
      );
      final focusState = tester.state(focusFinder);
      scroll.position.jumpTo(80);
      await tester.pump();
      expect(scroll.position.pixels, 80);
      await tester.pumpWidget(page(40));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        same(scroll),
      );
      expect(scroll.position.pixels, 80);
      expect(tester.state(focusFinder), same(focusState));
      expect(node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(Focus(focusNode: node, child: const Text('Reused'))),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('actual Canvas composition crossfades shelves by rail identity', (
    tester,
  ) async {
    Widget page(String rail) => MaterialApp(
      home: SizedBox(
        height: 500,
        child: buildHomeCanvasLayout(
          boardHeight: 500,
          cardAspect: 2 / 3,
          captionBand: 28,
          tabsHeight: 27,
          theater: false,
          artwork: const SizedBox.expand(),
          trailer: null,
          live: null,
          identity: const SizedBox(),
          tabs: const SizedBox(height: 27),
          shelfBuilder: (h, w, _) => buildHomeCanvasShelf(
            railKey: rail,
            itemCount: 2,
            cardWidth: w,
            cardHeight: h,
            itemBuilder: (_, index) => Text('$rail-$index'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(page('first'));
    expect(find.byType(ListView), findsOneWidget);
    await tester.pumpWidget(page('second'));
    expect(find.byType(ListView), findsNWidgets(2));
    expect(find.text('first-0'), findsOneWidget);
    expect(find.text('second-0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 201));
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('first-0'), findsNothing);
    expect(find.text('second-0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 220, child: child)),
);
