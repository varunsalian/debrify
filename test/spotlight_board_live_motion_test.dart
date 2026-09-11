import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
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
  final reducedMotion = ValueNotifier(false);
  tearDownAll(reducedMotion.dispose);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    TvMotionController.resetProfileScope();
  });

  tearDown(() {
    TvMotionController.resetProfileScope();
    ProfileRuntime.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
  });

  Future<({List<FocusNode> rows, ScrollPosition scroll})> mountBoard(
    WidgetTester tester,
  ) async {
    await TvMotionController.select(TvMotionProfile.smooth);
    reducedMotion.value = false;
    PlatformUtil.debugSetAndroidTvCached(true);
    PlatformUtil.debugSetTvOS(false);
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
        home: ValueListenableBuilder<bool>(
          valueListenable: reducedMotion,
          builder: (_, disabled, child) => MediaQuery(
            data: MediaQueryData(
              size: const Size(1280, 720),
              disableAnimations: disabled,
            ),
            child: child!,
          ),
          child: AppThemeScope(
            theme: AppTheme.fromDetail(
              DetailThemes.byId('signal'),
              motion: MotionTokens.legacy,
            ),
            child: TvMotionRoot(
              child: Scaffold(
                body: SpotlightBoard(
                  hero: [StremioMeta(id: 'hero', type: 'series', name: 'Hero')],
                  heroNode: hero,
                  heroAddon: null,
                  onHeroOpen: (_, __) {},
                  trailersEnabled: false,
                  // Keep real card focus and scroll handling while the policy changes.
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

  testWidgets('focused Spotlight consumers refresh without recreation', (
    tester,
  ) async {
    final f = await mountBoard(tester);
    final firstContext = f.rows[0].context;
    await TvMotionController.select(TvMotionProfile.snappy);
    await tester.pump();
    expect(f.rows[0].context, same(firstContext));
    expect(f.rows[0].hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(f.rows[1].hasPrimaryFocus, isTrue);
    expect(f.scroll.isScrollingNotifier.value, isFalse);

    await TvMotionController.select(TvMotionProfile.smooth);
    await tester.pump();
    final before = f.scroll.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(f.rows[2].hasPrimaryFocus, isTrue);
    expect(f.scroll.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 60));
    expect(f.scroll.pixels, greaterThan(before));
    await tester.pumpAndSettle();

    final focusedContext = f.rows[2].context;
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'incoming', dataGeneration: 2, sessionEpoch: 2),
    );
    await TvMotionController.warm();
    await tester.pump();
    expect(f.rows[2].context, same(focusedContext));
    expect(f.rows[2].hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(f.rows[1].hasPrimaryFocus, isTrue);
    expect(f.scroll.isScrollingNotifier.value, isFalse);

    await TvMotionController.select(TvMotionProfile.smooth);
    reducedMotion.value = true;
    await tester.pump();
    expect(f.rows[1].hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(f.rows[2].hasPrimaryFocus, isTrue);
    expect(f.scroll.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
