import 'observed_value.dart';
import 'package:debrify/features/discover/presentation/discover_stage_veils.dart';
import 'package:debrify/features/discover/presentation/discover_grid_dim.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
  for (final stage in [false, true]) {
    for (final androidTv in [false, true]) {
      testWidgets('veil ladder preserves stage=$stage Android TV=$androidTv', (
        tester,
      ) async {
        PlatformUtil.debugSetAndroidTvCached(androidTv);
        final showing = ObservedValue(false), theater = ObservedValue(false);
        addTearDown(() {
          showing.dispose();
          theater.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: DiscoverStageVeils(
              showing: showing,
              theater: theater,
              stage: stage,
            ),
          ),
        );
        final decorations = find.descendant(
          of: find.byType(DiscoverStageVeils),
          matching: find.byType(DecoratedBox),
        );
        double alpha() =>
            ((tester.widget<DecoratedBox>(decorations.first).decoration
                            as BoxDecoration)
                        .gradient
                    as LinearGradient)
                .colors
                .first
                .a;
        Duration duration() => tester
            .widget<TweenAnimationBuilder<double>>(
              find.byType(TweenAnimationBuilder<double>),
            )
            .duration;
        expect(
          tester.widgetList<DecoratedBox>(decorations).length,
          stage ? 3 : 2,
        );
        expect(alpha(), closeTo(stage ? .88 : .58, .001));
        showing.value = true;
        await tester.pump();
        expect(duration(), const Duration(milliseconds: 900));
        await tester.pump(const Duration(milliseconds: 900));
        expect(alpha(), closeTo(stage ? .56 : .34, .001));
        theater.value = true;
        await tester.pump();
        expect(duration(), const Duration(milliseconds: 1200));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(alpha(), closeTo(.10, .001));
        showing.value = false;
        theater.value = false;
        await tester.pump();
        expect(
          duration(),
          androidTv ? Duration.zero : const Duration(milliseconds: 250),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(alpha(), closeTo(stage ? .88 : .58, .001));
        expect(find.byType(Opacity), findsNothing);
        await tester.pumpWidget(const SizedBox());
        expect(showing.isObserved, isFalse);
        expect(theater.isObserved, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('grid dim fades out for theater and never intercepts input', (
    tester,
  ) async {
    final showing = ObservedValue(false), theater = ObservedValue(false);
    addTearDown(() {
      showing.dispose();
      theater.dispose();
    });
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('target'),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            DiscoverGridDim(showing: showing, theater: theater, leftInset: 320),
          ],
        ),
      ),
    );
    showing.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    final decoration = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(DiscoverGridDim),
        matching: find.byType(DecoratedBox),
      ),
    );
    final gradient =
        (decoration.decoration as BoxDecoration).gradient as LinearGradient;
    expect(gradient.colors.last.a, closeTo(.52, .001));
    expect(gradient.stops, [0, .15]);
    await tester.tap(find.byKey(const ValueKey('target')));
    expect(taps, 1);
    theater.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(
      find.descendant(
        of: find.byType(DiscoverGridDim),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('target')));
    expect(taps, 2);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
