import 'package:debrify/features/home/presentation/home_canvas_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (height, cardHeight) in [
    (400.0, 150.0),
    (720.0, 216.0),
    (1000.0, 220.0),
  ]) {
    testWidgets(
      'Canvas height $height retains geometry, surface state and shelf focus',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final node = FocusNode();
        addTearDown(node.dispose);
        final initialized = <String>[];
        final dimensions = <double>[];
        Widget host(
          bool theater, {
          double caption = 28,
          double tabs = 27,
          double? resizedHeight,
        }) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: resizedHeight ?? height,
              child: buildHomeCanvasLayout(
                boardHeight: resizedHeight ?? height,
                cardAspect: 16 / 9,
                captionBand: caption,
                tabsHeight: tabs,
                theater: theater,
                artwork: const SizedBox.expand(key: ValueKey('art')),
                trailer: _Surface(name: 'trailer', initialized: initialized),
                live: _Surface(name: 'live', initialized: initialized),
                identity: const SizedBox(
                  key: ValueKey('identity'),
                  width: 100,
                  height: 20,
                ),
                tabs: SizedBox(key: const ValueKey('tabs'), height: tabs),
                shelfBuilder: (h, w, favW) {
                  dimensions
                    ..clear()
                    ..addAll([h, w, favW]);
                  return TextField(
                    key: const ValueKey('shelf'),
                    focusNode: node,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(false));
        expect(dimensions[0], cardHeight);
        expect(dimensions[1], closeTo(cardHeight * 16 / 9, .00001));
        expect(dimensions[2], closeTo(cardHeight * 2 / 3, .00001));
        expect(
          tester.getSize(find.byKey(const ValueKey('art'))),
          Size(800, height),
        );
        final root = tester
            .widgetList<Stack>(find.byType(Stack))
            .firstWhere((s) => s.children.first.key == const ValueKey('art'));
        expect((root.children[1] as _Surface).name, 'trailer');
        expect((root.children[2] as _Surface).name, 'live');
        final padding = tester.widget<AnimatedPadding>(
          find.byType(AnimatedPadding),
        );
        expect(
          padding.padding,
          EdgeInsets.only(
            left: 48,
            right: 48,
            bottom: 22 + cardHeight + 28 + 10 + 12 + 27 + 25,
          ),
        );
        await tester.enterText(find.byType(TextField), 'Retained');
        node.requestFocus();
        await tester.pump();
        final editor = tester.state(find.byType(EditableText));
        await tester.pumpWidget(host(true));
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
          const Duration(milliseconds: 900),
        );
        await tester.pump(const Duration(milliseconds: 900));
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          .7,
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('identity'))),
          const Offset(48, 36),
        );
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
          const Offset(0, .12),
        );
        expect(node.hasFocus, isTrue);
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(initialized, ['trailer', 'live']);
        await tester.pumpWidget(host(false, caption: 48, tabs: 50));
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
          const Duration(milliseconds: 250),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).padding,
          EdgeInsets.only(
            left: 48,
            right: 48,
            bottom: 22 + cardHeight + 48 + 10 + 12 + 50 + 25,
          ),
        );
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('Retained'), findsOneWidget);
        expect(node.hasFocus, isTrue);
        expect(initialized, ['trailer', 'live']);
        await tester.pumpWidget(host(false, resizedHeight: height + 20));
        await tester.pump(const Duration(milliseconds: 250));
        expect(dimensions[0], ((height + 20) * .30).clamp(150.0, 220.0));
        expect(
          tester.getSize(find.byKey(const ValueKey('art'))),
          Size(800, height + 20),
        );
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(node.hasFocus, isTrue);
        expect(initialized, ['trailer', 'live']);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Canvas without native surfaces keeps artwork, identity and shelf',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 500,
            child: buildHomeCanvasLayout(
              boardHeight: 500,
              cardAspect: 2 / 3,
              captionBand: 28,
              tabsHeight: 27,
              theater: false,
              artwork: const SizedBox.expand(key: ValueKey('art')),
              trailer: null,
              live: null,
              identity: const Text('Identity'),
              tabs: const SizedBox(height: 27),
              shelfBuilder: (h, w, favW) {
                expect(w, favW);
                return const Text('Shelf');
              },
            ),
          ),
        ),
      );
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Shelf'), findsOneWidget);
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
