import 'observed_value.dart';
import 'package:debrify/features/discover/presentation/discover_grid_layout.dart';
import 'package:debrify/features/discover/presentation/discover_grid_dim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1000.0, 1600.0]) {
    testWidgets(
      'two-pane width $width preserves panel state, focus and overlay ordering',
      (tester) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final theater = ObservedValue(false),
            showing = ObservedValue(false),
            loading = ObservedValue(false);
        final takeover = ObservedValue(0.0);
        final focus = FocusNode();
        addTearDown(() {
          theater.dispose();
          showing.dispose();
          loading.dispose();
          takeover.dispose();
          focus.dispose();
        });
        double? panelWidth;
        const backdrop = SizedBox(key: ValueKey('backdrop'));
        const trailer = SizedBox(key: ValueKey('trailer'));
        const veils = SizedBox(key: ValueKey('veils'));
        Widget page() => MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) => buildDiscoverGridLayout(
                context,
                c: constraints,
                panel: Builder(
                  builder: (context) {
                    panelWidth = MediaQuery.sizeOf(context).width;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: TextField(
                        key: const ValueKey('query'),
                        focusNode: focus,
                      ),
                    );
                  },
                ),
                detailRail: const SizedBox(key: ValueKey('rail')),
                backdrop: backdrop,
                trailer: trailer,
                veils: veils,
                theater: theater,
                showing: showing,
                loading: loading,
                takeover: takeover,
                loadingIndicator: (visible) => Text('loading:$visible'),
                ambientIndicator: (visible) => Text('ambient:$visible'),
              ),
            ),
          ),
        );
        await tester.pumpWidget(page());
        final railWidth = (width * .375).clamp(320.0, 460.0);
        expect(
          tester.getSize(find.byKey(const ValueKey('rail'))).width,
          railWidth,
        );
        expect(panelWidth, width - railWidth);
        final stack = tester
            .widgetList<Stack>(find.byType(Stack))
            .firstWhere((stack) => stack.children.contains(trailer));
        expect((stack.children[1] as RepaintBoundary).child, same(backdrop));
        expect(stack.children[2], same(trailer));
        expect((stack.children[3] as RepaintBoundary).child, same(veils));
        expect(stack.children[4], isA<Row>());
        expect(stack.children[5], isA<DiscoverGridDim>());
        await tester.enterText(find.byType(TextField), 'retained query');
        focus.requestFocus();
        await tester.pump();
        final editor = tester.state(find.byType(EditableText));
        showing.value = true;
        loading.value = true;
        theater.value = true;
        takeover.value = .5;
        await tester.pump();
        expect(find.text('loading:true'), findsOneWidget);
        expect(find.text('ambient:false'), findsOneWidget);
        final opacity = tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .toList();
        expect(opacity.map((w) => w.opacity), [.15, .12]);
        expect(
          opacity.every(
            (w) => w.duration == const Duration(milliseconds: 1200),
          ),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 1300));
        expect(focus.hasFocus, isTrue);
        loading.value = false;
        theater.value = false;
        await tester.pump();
        expect(find.text('ambient:true'), findsOneWidget);
        expect(
          tester
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .every((w) => w.duration == const Duration(milliseconds: 250)),
          isTrue,
        );
        tester.view.physicalSize = Size(width + 100, 600);
        await tester.pumpWidget(page());
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(find.text('retained query'), findsOneWidget);
        expect(focus.hasFocus, isTrue);
        expect(
          panelWidth,
          width + 100 - ((width + 100) * .375).clamp(320.0, 460.0),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(theater.isObserved, isFalse);
        expect(takeover.isObserved, isFalse);
      },
    );
  }
}
