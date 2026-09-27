import 'package:debrify/features/discover/presentation/discover_stage_layout.dart';
import 'package:debrify/widgets/see_all/discover_shelf_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'observed_value.dart';

void main() {
  for (final size in [
    const Size(720, 420),
    const Size(1000, 600),
    const Size(1600, 900),
  ]) {
    testWidgets('Stage geometry and theater retain shelf state at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
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
      double? identityWidth, identityBudget;
      DiscoverShelfMetrics? metrics;
      var identityBuilds = 0;
      const backdrop = SizedBox(key: ValueKey('backdrop'));
      const trailer = SizedBox(key: ValueKey('trailer'));
      const veils = SizedBox(key: ValueKey('veils'));
      Widget page() => MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => buildDiscoverStageLayout(
              context,
              constraints: constraints,
              panel: Builder(
                builder: (context) {
                  metrics = DiscoverShelfScope.of(context);
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: TextField(focusNode: focus),
                  );
                },
              ),
              buildIdentity: (width, budget) {
                identityWidth = width;
                identityBudget = budget;
                identityBuilds++;
                return const SizedBox(key: ValueKey('identity'));
              },
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
      final cardHeight = (size.height * .30).clamp(140.0, 200.0);
      expect(metrics!.cardHeight, cardHeight);
      expect(metrics!.hPad, 24);
      expect(identityWidth, (size.width * .5).clamp(320.0, 560.0));
      expect(identityBudget, size.height - 62 - (metrics!.columnHeight + 22));
      final stageStack = tester
          .widgetList<Stack>(find.byType(Stack))
          .firstWhere((widget) => widget.children.contains(trailer));
      expect((stageStack.children[1] as RepaintBoundary).child, same(backdrop));
      expect(stageStack.children[2], same(trailer));
      expect((stageStack.children[3] as RepaintBoundary).child, same(veils));
      final padding = tester.widget<AnimatedPadding>(
        find.byType(AnimatedPadding),
      );
      expect(
        padding.padding,
        EdgeInsets.only(top: 62, bottom: metrics!.columnHeight + 22),
      );
      await tester.enterText(find.byType(TextField), 'retained');
      focus.requestFocus();
      await tester.pump();
      final editor = tester.state(find.byType(EditableText));
      final builds = identityBuilds;
      final budget = identityBudget;
      showing.value = true;
      loading.value = true;
      theater.value = true;
      takeover.value = .5;
      await tester.pump();
      expect(
        tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).padding,
        const EdgeInsets.only(top: 30),
      );
      expect(
        tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
        Alignment.topLeft,
      );
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        .7,
      );
      expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        const Offset(0, .12),
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      expect(
        tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
        const Duration(milliseconds: 900),
      );
      expect(find.text('loading:true'), findsOneWidget);
      expect(find.text('ambient:false'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 950));
      expect(identityBuilds, builds);
      expect(identityBudget, budget);
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(focus.hasFocus, isTrue);
      loading.value = false;
      theater.value = false;
      await tester.pump();
      expect(
        tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
        const Duration(milliseconds: 250),
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      expect(find.text('ambient:true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      tester.view.physicalSize = Size(size.width + 100, size.height + 100);
      await tester.pumpWidget(page());
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        metrics!.cardHeight,
        ((size.height + 100) * .30).clamp(140.0, 200.0),
      );
      expect(
        identityBudget,
        size.height + 100 - 62 - (metrics!.columnHeight + 22),
      );
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(find.text('retained'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(theater.isObserved, isFalse);
      expect(takeover.isObserved, isFalse);
    });
  }
}
