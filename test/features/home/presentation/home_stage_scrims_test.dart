import 'package:debrify/features/home/presentation/home_stage_scrims.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final variant in HomeStageScrimVariant.values) {
    testWidgets(
      '${variant.name} shading fades out in 900ms and returns in 250ms',
      (tester) async {
        await tester.pumpWidget(_host(variant, false));
        double opacity() => tester
            .widget<FadeTransition>(find.byType(FadeTransition))
            .opacity
            .value;
        expect(opacity(), 1);
        final decorations = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .toList();
        expect(
          decorations.length,
          variant == HomeStageScrimVariant.seam ? 2 : 3,
        );
        for (final box in find.byType(DecoratedBox).evaluate()) {
          expect((box.renderObject as RenderBox).size, const Size(640, 360));
        }
        await tester.pumpWidget(_host(variant, true));
        await tester.pump(const Duration(milliseconds: 450));
        expect(opacity(), closeTo(1 - Curves.easeOut.transform(.5), .00001));
        await tester.pump(const Duration(milliseconds: 450));
        expect(opacity(), 0);
        await tester.pumpWidget(_host(variant, false));
        await tester.pump(const Duration(milliseconds: 125));
        expect(opacity(), closeTo(Curves.easeOut.transform(.5), .00001));
        await tester.pump(const Duration(milliseconds: 125));
        expect(opacity(), 1);
        // The fade updates opacity rather than rebuilding or replacing gradients.
        final after = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .toList();
        for (var i = 0; i < decorations.length; i++) {
          expect(identical(decorations[i], after[i]), isTrue);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('changing the stage variant retains the ongoing theater fade', (
    tester,
  ) async {
    await tester.pumpWidget(_host(HomeStageScrimVariant.canvas, false));
    await tester.pumpWidget(_host(HomeStageScrimVariant.canvas, true));
    await tester.pump(const Duration(milliseconds: 300));
    final before = tester
        .widget<FadeTransition>(find.byType(FadeTransition))
        .opacity
        .value;
    await tester.pumpWidget(
      _host(HomeStageScrimVariant.seam, true, width: 400),
    );
    final after = tester
        .widget<FadeTransition>(find.byType(FadeTransition))
        .opacity
        .value;
    expect(after, before);
    expect(find.byType(DecoratedBox), findsNWidgets(2));
    for (final box in find.byType(DecoratedBox).evaluate()) {
      expect((box.renderObject as RenderBox).size, const Size(400, 360));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value,
      0,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  HomeStageScrimVariant variant,
  bool theater, {
  double width = 640,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(
      width: width,
      height: 360,
      child: HomeStageScrims(variant: variant, theater: theater),
    ),
  ),
);
