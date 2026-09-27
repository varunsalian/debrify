import 'package:debrify/features/home/presentation/home_promenade_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [100.0, 400.0, 1000.0]) {
    testWidgets(
      'Promenade width $width preserves strip padding and state through theater and resize',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final node = FocusNode();
        addTearDown(node.dispose);
        final initialized = <String>[];
        final built = <int>{};
        Widget page(
          bool theater, {
          double? resizedWidth,
          double labelHeight = 27,
        }) {
          final w = resizedWidth ?? width;
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: w,
                height: 500,
                child: buildHomePromenadeLayout(
                  boardWidth: w,
                  stripHeight: 180,
                  cellWidth: 240,
                  labelHeight: labelHeight,
                  theater: theater,
                  railKey: 'stable',
                  itemCount: 100,
                  artwork: const SizedBox.expand(key: ValueKey('art')),
                  trailer: _Surface(name: 'trailer', initialized: initialized),
                  live: _Surface(name: 'live', initialized: initialized),
                  identity: const SizedBox(
                    key: ValueKey('identity'),
                    width: 100,
                    height: 20,
                  ),
                  label: SizedBox(height: labelHeight),
                  itemBuilder: (_, index) {
                    built.add(index);
                    return SizedBox(
                      key: ValueKey('cell-$index'),
                      height: 140,
                      child: index == 0
                          ? Focus(focusNode: node, child: const Text('First'))
                          : Text('Cell $index'),
                    );
                  },
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(page(false));
        final padding = ((width - 240) / 2).clamp(0.0, width / 2);
        expect(
          tester.widget<ListView>(find.byType(ListView)).padding,
          EdgeInsets.symmetric(horizontal: padding),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('cell-0'))),
          const Size(240, 140),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('cell-0'))).dx,
          padding + 7,
        );
        expect(built.length, lessThan(20));
        final root = tester
            .widgetList<Stack>(find.byType(Stack))
            .firstWhere(
              (stack) => stack.children.first.key == const ValueKey('art'),
            );
        expect((root.children[1] as _Surface).name, 'trailer');
        expect((root.children[2] as _Surface).name, 'live');
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).padding,
          const EdgeInsets.only(
            left: 48,
            right: 48,
            bottom: 24 + 180 + 14 + 27 + 26,
          ),
        );
        node.requestFocus();
        await tester.pump();
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        scroll.position.jumpTo(80);
        await tester.pump();
        await tester.pumpWidget(page(true));
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
          const Duration(milliseconds: 900),
        );
        await tester.pump(const Duration(milliseconds: 900));
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('identity'))),
          const Offset(48, 36),
        );
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          .7,
        );
        expect(node.hasFocus, isTrue);
        expect(
          tester.state<ScrollableState>(find.byType(Scrollable)),
          same(scroll),
        );
        expect(scroll.position.pixels, 80);
        expect(initialized, ['trailer', 'live']);
        await tester.pumpWidget(
          page(false, resizedWidth: width + 50, labelHeight: 50),
        );
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
          const Duration(milliseconds: 250),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).padding,
          const EdgeInsets.only(
            left: 48,
            right: 48,
            bottom: 24 + 180 + 14 + 50 + 26,
          ),
        );
        expect(
          tester.state<ScrollableState>(find.byType(Scrollable)),
          same(scroll),
        );
        expect(scroll.position.pixels, 80);
        expect(node.hasFocus, isTrue);
        expect(initialized, ['trailer', 'live']);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Promenade without native surfaces preserves keyed rail replacement',
    (tester) async {
      Widget page(String rail) => MaterialApp(
        home: SizedBox(
          height: 500,
          child: buildHomePromenadeLayout(
            boardWidth: 800,
            stripHeight: 180,
            cellWidth: 240,
            labelHeight: 27,
            theater: false,
            railKey: rail,
            itemCount: 2,
            artwork: const SizedBox.expand(),
            trailer: null,
            live: null,
            identity: const Text('Identity'),
            label: const Text('Label'),
            itemBuilder: (_, index) => Text('$rail-$index'),
          ),
        ),
      );
      await tester.pumpWidget(page('first'));
      final first = tester.state<ScrollableState>(find.byType(Scrollable));
      await tester.pumpWidget(page('second'));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        isNot(same(first)),
      );
      expect(find.text('second-0'), findsOneWidget);
      expect(find.text('first-0'), findsNothing);
      expect(find.byType(_Surface), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _Surface extends StatefulWidget {
  const _Surface({required this.name, required this.initialized});
  final String name;
  final List<String> initialized;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  @override
  void initState() {
    super.initState();
    widget.initialized.add(widget.name);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
