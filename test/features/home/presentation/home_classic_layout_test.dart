import 'package:debrify/features/home/presentation/home_classic_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

void main() {
  for (final scenario in [
    (899.0, false, 196.0),
    (900.0, false, 300.0),
    (1280.0, true, 200.0),
  ]) {
    testWidgets(
      'Classic geometry and layer ownership for width ${scenario.$1}, TV=${scenario.$2}',
      (tester) async {
        final takeover = ObservedValue(0.0);
        final node = FocusNode();
        addTearDown(takeover.dispose);
        addTearDown(node.dispose);
        final init = <String, int>{};
        final calls = <String>[];
        final heights = <double>[];
        final budgets = <double>[];
        final boardKey = GlobalKey();
        final trailerKey = GlobalKey();
        final liveKey = GlobalKey();
        Widget page(double height) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: height,
              child: buildHomeClassicLayout(
                isTelevision: scenario.$2,
                viewportWidth: scenario.$1,
                tvHeroBudget: (boardHeight) {
                  budgets.add(boardHeight);
                  return boardHeight / 2;
                },
                trailerActive: true,
                takeover: takeover,
                boardBuilder: (heroHeight) {
                  calls.add('board');
                  heights.add(heroHeight);
                  return Column(
                    key: boardKey,
                    children: [
                      SizedBox(key: const ValueKey('hero'), height: heroHeight),
                      Expanded(child: TextField(focusNode: node)),
                    ],
                  );
                },
                trailerBuilder: (heroHeight) {
                  calls.add('trailer');
                  heights.add(heroHeight);
                  return _Surface(
                    key: trailerKey,
                    name: 'trailer',
                    initialized: init,
                  );
                },
                liveBuilder: (heroHeight) {
                  calls.add('live');
                  heights.add(heroHeight);
                  return _Surface(
                    key: liveKey,
                    name: 'live',
                    initialized: init,
                  );
                },
                infoBuilder: () {
                  calls.add('info');
                  return const IgnorePointer(
                    child: SizedBox(key: ValueKey('info')),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpWidget(page(400));
        expect(calls, ['board', 'trailer', 'live', 'info']);
        expect(heights, everyElement(scenario.$3));
        expect(budgets, scenario.$2 ? [400.0] : isEmpty);
        expect(
          tester.getSize(find.byKey(const ValueKey('hero'))).height,
          scenario.$3,
        );
        final stack = tester
            .widgetList<Stack>(find.byType(Stack))
            .firstWhere(
              (w) =>
                  w.children.length == 4 &&
                  w.children[1] is Positioned &&
                  w.children[2] is Positioned,
            );
        expect((stack.children[1] as Positioned).child.key, trailerKey);
        expect((stack.children[2] as Positioned).child.key, liveKey);
        expect(
          (stack.children[3] as IgnorePointer).child!.key,
          const ValueKey('info'),
        );
        await tester.enterText(find.byType(TextField), 'Retained');
        node.requestFocus();
        await tester.pump();
        final editor = tester.state(find.byType(EditableText));
        final originalBoard = boardKey.currentContext;
        final callsBefore = calls.length;
        takeover.value = 1;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 241));
        expect(calls.length, callsBefore);
        expect(init, {'trailer': 1, 'live': 1});
        expect(boardKey.currentContext, same(originalBoard));
        expect(
          tester.getSize(find.byKey(const ValueKey('hero'))).height,
          scenario.$3,
        );
        expect(node.hasFocus, isTrue);
        takeover.value = 0;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 241));
        await tester.pumpWidget(page(500));
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('Retained'), findsOneWidget);
        expect(node.hasFocus, isTrue);
        expect(init, {'trailer': 1, 'live': 1});
        expect(
          tester.getSize(find.byKey(const ValueKey('hero'))).height,
          scenario.$2 ? 250 : scenario.$3,
        );
        await tester.pumpWidget(const SizedBox());
        expect(takeover.isObserved, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'inactive trailers do not construct native surfaces or subscribe to takeover',
    (tester) async {
      final takeover = ObservedValue(1.0);
      addTearDown(takeover.dispose);
      var nativeBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: buildHomeClassicLayout(
            isTelevision: false,
            viewportWidth: 700,
            tvHeroBudget: (_) => throw StateError('Off-TV budget must not run'),
            trailerActive: false,
            takeover: takeover,
            boardBuilder: (height) => Text('Board $height'),
            trailerBuilder: (_) {
              nativeBuilds++;
              return const SizedBox();
            },
            liveBuilder: (_) {
              nativeBuilds++;
              return const SizedBox();
            },
            infoBuilder: () {
              nativeBuilds++;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(find.text('Board 196.0'), findsOneWidget);
      expect(nativeBuilds, 0);
      expect(takeover.isObserved, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _Surface extends StatefulWidget {
  const _Surface({super.key, required this.name, required this.initialized});
  final String name;
  final Map<String, int> initialized;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  @override
  void initState() {
    super.initState();
    widget.initialized.update(widget.name, (v) => v + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) =>
      const IgnorePointer(child: SizedBox.expand());
}
