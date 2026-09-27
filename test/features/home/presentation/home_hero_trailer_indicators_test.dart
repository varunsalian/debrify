import 'package:debrify/features/home/presentation/home_hero_trailer_indicators.dart';
import 'package:debrify/features/home/presentation/home_spotlight_search_button.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  home: AppThemeScope(
    theme: AppThemes.legacy,
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('loading wave stops while hidden and restarts when shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const HomeHeroTrailerLoadingPill(visible: true)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(
      host(const HomeHeroTrailerLoadingPill(visible: false)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, 0);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await tester.pumpWidget(
      host(const HomeHeroTrailerLoadingPill(visible: true)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final tv in [false, true]) {
    testWidgets('ambient pulse visibility and disposal retain TV=$tv policy', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(tv);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      await tester.pumpWidget(host(const HomeHeroAmbientChip(visible: true)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.transientCallbackCount, tv ? 0 : greaterThan(0));
      await tester.pumpWidget(host(const HomeHeroAmbientChip(visible: false)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'floating search button retains target size and dispatches one tap',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(HomeSpotlightSearchButton(onTap: () => taps++)),
      );
      expect(
        tester.getSize(find.byType(HomeSpotlightSearchButton)),
        const Size(40, 40),
      );
      await tester.tap(find.byIcon(Icons.search_rounded));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
