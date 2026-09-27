import 'package:debrify/features/home/presentation/home_trailer_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

void main() {
  testWidgets(
    'inactive transitions return the original child without subscriptions',
    (tester) async {
      final showing = ObservedValue(true);
      final takeover = ObservedValue(1.0);
      addTearDown(showing.dispose);
      addTearDown(takeover.dispose);
      const child = Text('Board');
      final dimmed = buildHomeTrailerRowsDim(
        active: false,
        showing: showing,
        rows: child,
      );
      final receded = buildHomeTrailerBoardRecede(
        active: false,
        takeover: takeover,
        board: dimmed,
      );
      expect(dimmed, same(child));
      expect(receded, same(child));
      await tester.pumpWidget(_host(receded));
      expect(showing.isObserved, isFalse);
      expect(takeover.isObserved, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'row veil fades in slowly, out quickly, and never intercepts taps',
    (tester) async {
      final showing = ObservedValue(false);
      addTearDown(showing.dispose);
      var taps = 0;
      final childKey = GlobalKey();
      final child = GestureDetector(
        key: childKey,
        onTap: () => taps++,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox(width: 200, height: 100, child: Text('Rows')),
      );
      await tester.pumpWidget(
        _host(
          buildHomeTrailerRowsDim(active: true, showing: showing, rows: child),
        ),
      );
      final original = childKey.currentContext;
      expect(showing.isObserved, isTrue);
      AnimatedOpacity veil() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(AnimatedOpacity),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(veil().opacity, 0);
      showing.value = true;
      await tester.pump();
      expect(veil().duration, const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 450));
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 451));
      expect(opacity(), 1);
      await tester.tap(find.text('Rows'));
      expect(taps, 1);
      expect(childKey.currentContext, same(original));
      showing.value = false;
      await tester.pump();
      expect(veil().duration, const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 251));
      expect(opacity(), 0);
      expect(childKey.currentContext, same(original));
      await tester.pumpWidget(const SizedBox());
      expect(showing.isObserved, isFalse);
      showing.value = true;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'takeover retains focus, scroll and child state while muting hidden tickers',
    (tester) async {
      final takeover = ObservedValue(0.0);
      final node = FocusNode();
      final scroll = ScrollController();
      addTearDown(takeover.dispose);
      addTearDown(node.dispose);
      addTearDown(scroll.dispose);
      var opens = 0;
      var builds = 0;
      final key = GlobalKey();
      final board = Builder(
        key: key,
        builder: (context) {
          builds++;
          return Focus(
            focusNode: node,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                opens++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              height: 100,
              child: ListView(
                controller: scroll,
                children: const [SizedBox(height: 500, child: Text('Board'))],
              ),
            ),
          );
        },
      );
      await tester.pumpWidget(
        _host(
          buildHomeTrailerBoardRecede(
            active: true,
            takeover: takeover,
            board: board,
          ),
        ),
      );
      final original = key.currentContext;
      node.requestFocus();
      await tester.pump();
      scroll.jumpTo(80);
      final beforeBuilds = builds;
      takeover.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final opacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(opacity, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 121));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
      expect(TickerMode.valuesOf(key.currentContext!).enabled, isFalse);
      expect(node.hasFocus, isTrue);
      expect(scroll.offset, 80);
      expect(key.currentContext, same(original));
      expect(builds, beforeBuilds);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opens, 1);
      takeover.value = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 241));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      expect(TickerMode.valuesOf(key.currentContext!).enabled, isTrue);
      expect(node.hasFocus, isTrue);
      expect(scroll.offset, 80);
      expect(key.currentContext, same(original));
      await tester.pumpWidget(const SizedBox());
      expect(takeover.isObserved, isFalse);
      expect(scroll.hasClients, isFalse);
      takeover.value = .5;
      expect(tester.takeException(), isNull);
    },
  );

  for (final target in [-1.0, 2.0]) {
    testWidgets('takeover clamps target $target into legal opacity', (
      tester,
    ) async {
      final takeover = ObservedValue(target);
      addTearDown(takeover.dispose);
      await tester.pumpWidget(
        _host(
          buildHomeTrailerBoardRecede(
            active: true,
            takeover: takeover,
            board: const Text('Board'),
          ),
        ),
      );
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        target < 0 ? 1 : 0,
      );
      await tester.pumpWidget(const SizedBox());
      expect(takeover.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);
