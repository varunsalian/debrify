import 'package:debrify/features/home/presentation/home_hero_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

void main() {
  for (final boxed in [false, true]) {
    testWidgets(
      'boxed=$boxed preserves independent image, identity and meta fades',
      (tester) async {
        final showing = ObservedValue(false);
        final live = ObservedValue(false);
        addTearDown(showing.dispose);
        addTearDown(live.dispose);
        final transitions = HomeHeroTransitions(
          boxedTrailer: boxed,
          showing: showing,
          liveTakeover: live,
        );
        const image = Text('image');
        const identity = Text('identity');
        const meta = Text('meta');
        final wrappedImage = transitions.fadeBackdropForTrailer(image);
        final wrappedIdentity = transitions.fadeIdentityForTrailer(identity);
        final wrappedMeta = transitions.fadeMetaForTrailer(meta);
        expect(identical(wrappedImage, image), !boxed);
        expect(identical(wrappedIdentity, identity), boxed);
        expect(identical(wrappedMeta, meta), !boxed);
        await tester.pumpWidget(
          MaterialApp(
            home: Column(
              children: [
                wrappedImage,
                wrappedIdentity,
                wrappedMeta,
                transitions.fadeForLiveTakeover(const Text('live')),
              ],
            ),
          ),
        );
        showing.value = true;
        await tester.pump();
        final fades = tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .toList();
        expect(
          fades.map((f) => f.duration.inMilliseconds),
          boxed ? [650, 480, 340] : [650, 340],
        );
        expect(fades.map((f) => f.opacity), boxed ? [0, 0, 1] : [0, 1]);
        live.value = true;
        await tester.pump();
        expect(
          tester
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .last
              .opacity,
          0,
        );
        showing.value = false;
        await tester.pump();
        expect(
          tester
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .first
              .opacity,
          1,
        );
        await tester.pumpWidget(const SizedBox());
        expect(showing.isObserved, isFalse);
        expect(live.isObserved, isFalse);
      },
    );
  }
  test('absent signals return original children', () {
    const transitions = HomeHeroTransitions(boxedTrailer: true);
    const child = Text('unchanged');
    expect(transitions.fadeBackdropForTrailer(child), same(child));
    expect(transitions.fadeIdentityForTrailer(child), same(child));
    expect(transitions.fadeMetaForTrailer(child), same(child));
    expect(transitions.fadeForLiveTakeover(child), same(child));
  });
}
