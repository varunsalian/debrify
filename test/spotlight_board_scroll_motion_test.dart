import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/tv_motion_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
  });

  Future<({List<FocusNode> rows, ScrollPosition scroll})> mountBoard(
    WidgetTester tester, {
    required TvMotionProfile profile,
    bool tv = true,
    bool tvOS = false,
    bool reduced = false,
  }) async {
    PlatformUtil.debugSetAndroidTvCached(tv);
    PlatformUtil.debugSetTvOS(tvOS);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    final hero = FocusNode(debugLabel: 'hero');
    final rows = List.generate(6, (i) => FocusNode(debugLabel: 'shelf-$i'));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      hero.dispose();
      for (final node in rows) {
        node.dispose();
      }
      tester.view.reset();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(1280, 720),
            disableAnimations: reduced,
          ),
          child: AppThemeScope(
            theme: AppTheme.fromDetail(
              DetailThemes.byId('signal'),
              motion: MotionTokens.legacy,
            ),
            child: TvMotionScope(
              profile: profile,
              child: Scaffold(
                body: SpotlightBoard(
                  hero: [StremioMeta(id: 'hero', type: 'series', name: 'Hero')],
                  heroNode: hero,
                  heroAddon: null,
                  onHeroOpen: (_, __) {},
                  trailersEnabled: false,
                  // Keyboard navigation also exercises the off-TV scroll path.
                  dpad: true,
                  sections: [
                    for (var i = 0; i < rows.length; i++)
                      SpotlightShelf(
                        id: 'shelf-$i',
                        title: 'Shelf $i',
                        nodes: [rows[i]],
                        items: [
                          SpotlightCard(
                            title: 'Card $i',
                            rating: 8.1,
                            shape: SpotlightCardShape.wide,
                            onOpen: () {},
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    hero.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(rows.first.hasPrimaryFocus, isTrue);
    expect(rows[1].context?.mounted, isTrue);

    final scroll = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byType(SpotlightBoard),
            matching: find.byType(Scrollable),
          ),
        )
        .singleWhere((state) => state.axisDirection == AxisDirection.down)
        .position;
    return (rows: rows, scroll: scroll);
  }

  for (final scenario in [
    (
      name: 'TV Smooth',
      tvOS: false,
      profile: TvMotionProfile.smooth,
      tv: true,
      reduced: false,
      milliseconds: 260,
    ),
    (
      name: 'TV Snappy',
      tvOS: false,
      profile: TvMotionProfile.snappy,
      tv: true,
      reduced: false,
      milliseconds: 0,
    ),
    (
      name: 'TV Smooth with reduced motion',
      tvOS: false,
      profile: TvMotionProfile.smooth,
      tv: true,
      reduced: true,
      milliseconds: 0,
    ),
    (
      name: 'off-TV Smooth',
      tvOS: false,
      profile: TvMotionProfile.smooth,
      tv: false,
      reduced: false,
      milliseconds: 220,
    ),
    (
      name: 'off-TV Snappy',
      tvOS: false,
      profile: TvMotionProfile.snappy,
      tv: false,
      reduced: false,
      milliseconds: 220,
    ),
    (
      name: 'tvOS default Snappy',
      profile: TvMotionProfile.snappy,
      tv: false,
      tvOS: true,
      reduced: false,
      milliseconds: 220,
    ),
    (
      name: 'tvOS explicit Smooth',
      profile: TvMotionProfile.smooth,
      tv: false,
      tvOS: true,
      reduced: false,
      milliseconds: 260,
    ),
    (
      name: 'off-TV reduced motion',
      profile: TvMotionProfile.smooth,
      tv: false,
      tvOS: false,
      reduced: true,
      milliseconds: 0,
    ),
  ]) {
    testWidgets('${scenario.name}: vertical DPAD preserves scroll timing', (
      tester,
    ) async {
      final f = await mountBoard(
        tester,
        profile: scenario.profile,
        tv: scenario.tv,
        tvOS: scenario.tvOS,
        reduced: scenario.reduced,
      );
      final start = f.scroll.pixels;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(); // Start the animation clock without advancing time.
      expect(f.rows[1].hasPrimaryFocus, isTrue);
      final immediate = f.scroll.pixels;
      expect(f.scroll.isScrollingNotifier.value, scenario.milliseconds > 0);

      await tester.pump(const Duration(milliseconds: 60));
      final intermediate = f.scroll.pixels;
      await tester.pump(const Duration(milliseconds: 161));
      expect(f.scroll.isScrollingNotifier.value, scenario.milliseconds > 221);
      await tester.pump(const Duration(milliseconds: 79));
      final end = f.scroll.pixels;
      expect(end, greaterThan(start));
      expect(f.scroll.isScrollingNotifier.value, isFalse);

      if (scenario.milliseconds == 0) {
        expect(immediate, closeTo(end, 0.1));
        expect(intermediate, closeTo(end, 0.1));
      } else {
        expect(immediate, closeTo(start, 0.1));
        expect(intermediate, greaterThan(start));
        expect(intermediate, lessThan(end));
        expect(
          intermediate,
          closeTo(
            start +
                (end - start) *
                    Curves.easeOutCubic.transform(60 / scenario.milliseconds),
            0.5,
          ),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Smooth: repeated Down then Up settles at the latest shelf', (
    tester,
  ) async {
    final f = await mountBoard(tester, profile: TvMotionProfile.smooth);
    final start = f.scroll.pixels;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(f.rows[1].hasPrimaryFocus, isTrue);
    expect(f.scroll.isScrollingNotifier.value, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(f.rows[2].hasPrimaryFocus, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(f.rows[1].hasPrimaryFocus, isTrue);
    final destination = f.scroll.pixels;

    // A settled visit to the same shelf must produce the same target.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(f.scroll.pixels, closeTo(start, 0.5));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(f.scroll.pixels, closeTo(destination, 0.5));
    expect(tester.takeException(), isNull);
  });
}
