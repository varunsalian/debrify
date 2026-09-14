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
  test(
    'TV transitions stay lightweight and other routes use short timings',
    () {
      const builder = TvAwarePageTransitionsBuilder();
      PlatformUtil.debugSetAndroidTvCached(true);
      expect(builder.transitionDuration, const Duration(milliseconds: 180));
      expect(
        builder.reverseTransitionDuration,
        const Duration(milliseconds: 140),
      );
      PlatformUtil.debugSetAndroidTvCached(false);
      expect(builder.transitionDuration, const Duration(milliseconds: 240));
      expect(
        builder.reverseTransitionDuration,
        const Duration(milliseconds: 180),
      );
    },
  );
  test('every platform uses the shared builder, with native iOS gestures', () {
    for (final platform in TargetPlatform.values) {
      final builder = AppThemeAdapter.pageTransitions.builders[platform];
      expect(builder, isA<TvAwarePageTransitionsBuilder>());
      expect(
        (builder! as TvAwarePageTransitionsBuilder).preserveSwipeBack,
        platform == TargetPlatform.iOS,
      );
    }
  });

  testWidgets('phone and desktop lift fades out for reduced motion', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(false);
    final controller = _CountedController()..value = 0.5;
    addTearDown(controller.dispose);
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    for (final reduced in [false, true]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Builder(
              builder: (context) =>
                  const TvAwarePageTransitionsBuilder().buildTransitions(
                    route,
                    context,
                    controller,
                    const AlwaysStoppedAnimation(0),
                    const SizedBox(),
                  ),
            ),
          ),
        ),
      );
      expect(
        find.byType(FadeTransition),
        reduced ? findsNothing : findsOneWidget,
      );
      expect(
        find.byType(SlideTransition),
        reduced ? findsNothing : findsOneWidget,
      );
      expect(controller.statusListeners, 0);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('material routes push and pop on every platform', (tester) async {
    PlatformUtil.debugSetAndroidTvCached(false);
    for (final reduced in [false, true]) {
      for (final platform in TargetPlatform.values) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey((platform, reduced)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            theme: ThemeData(
              platform: platform,
              pageTransitionsTheme: AppThemeAdapter.pageTransitions,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('Destination')),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (platform == TargetPlatform.iOS && reduced) {
          final slides = tester.widgetList<SlideTransition>(
            find.byType(SlideTransition),
          );
          expect(slides, isNotEmpty);
          for (final slide in slides) {
            expect(slide.position.value, Offset.zero);
          }
        }
        await tester.pumpAndSettle();
        expect(find.text('Destination'), findsOneWidget);
        if (platform == TargetPlatform.iOS) {
          final swipe = await tester.startGesture(const Offset(1, 300));
          await swipe.moveBy(const Offset(650, 0));
          await swipe.up();
        } else {
          final context = tester.element(find.text('Destination'));
          Navigator.of(context).pop();
        }
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
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
