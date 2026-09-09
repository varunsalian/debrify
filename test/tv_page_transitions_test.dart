import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountedController extends AnimationController {
  _CountedController() : super(vsync: const TestVSync());
  int statusListeners = 0;
  @override
  void addStatusListener(AnimationStatusListener listener) {
    statusListeners++;
    super.addStatusListener(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    statusListeners--;
    super.removeStatusListener(listener);
  }
}

void main() {
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
  test('TV route durations are short; phone durations remain stock', () {
    const builder = TvAwarePageTransitionsBuilder();
    PlatformUtil.debugSetAndroidTvCached(true);
    expect(builder.transitionDuration, const Duration(milliseconds: 180));
    expect(
      builder.reverseTransitionDuration,
      const Duration(milliseconds: 140),
    );
    PlatformUtil.debugSetAndroidTvCached(false);
    const stock = ZoomPageTransitionsBuilder();
    expect(builder.transitionDuration, stock.transitionDuration);
    expect(builder.reverseTransitionDuration, stock.reverseTransitionDuration);
  });
  testWidgets(
    'TV fade respects reduced motion and retains no status listeners',
    (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      final controller = _CountedController();
      addTearDown(controller.dispose);
      final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      const child = SizedBox(key: ValueKey('content'));
      for (final reduced in [false, true]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Builder(
              builder: (context) {
                Widget result = child;
                for (var i = 0; i < 30; i++) {
                  result = const TvAwarePageTransitionsBuilder()
                      .buildTransitions(
                        route,
                        context,
                        controller,
                        const AlwaysStoppedAnimation(0),
                        child,
                      );
                }
                return result;
              },
            ),
          ),
        );
        expect(
          find.byType(FadeTransition),
          reduced ? findsNothing : findsOneWidget,
        );
        expect(controller.statusListeners, 0);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
