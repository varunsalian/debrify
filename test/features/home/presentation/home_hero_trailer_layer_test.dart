import 'package:debrify/features/home/presentation/home_hero_trailer_layer.dart';
import 'package:debrify/ui/core/trailer_indicators.dart';
import 'package:debrify/ui/core/spotlight_search_button.dart';
import 'package:debrify/models/youtube_resolved_streams.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

Widget host(Widget child) => MaterialApp(
  home: AppThemeScope(
    theme: AppThemes.legacy,
    child: MediaQuery(
      data: const MediaQueryData(viewPadding: EdgeInsets.only(top: 24)),
      child: child,
    ),
  ),
);

void main() {
  setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets(
    'trailer signals retain same URL identity and release old listeners',
    (tester) async {
      const streams = YoutubeResolvedStreams(
        playUrl: 'https://fixture.invalid/a',
        audioUrl: 'https://fixture.invalid/audio',
      );
      final first = ObservedValue<YoutubeResolvedStreams?>(streams);
      final second = ObservedValue<YoutubeResolvedStreams?>(streams);
      final loading = ObservedValue(false);
      final nextLoading = ObservedValue(true);
      final takeover = ObservedValue(0.2);
      for (final value in [first, second, loading, nextLoading, takeover]) {
        addTearDown(value.dispose);
      }
      final playing = <bool>[];
      Widget layer(
        ObservedValue<YoutubeResolvedStreams?> source,
        ObservedValue<bool> busy, {
        bool bleed = false,
      }) => host(
        HomeHeroTrailerLayer(
          trailer: source,
          loading: busy,
          heroHeight: 300,
          volume: 25,
          isTelevision: true,
          fullBleed: bleed,
          takeover: takeover,
          onPlayingChanged: playing.add,
        ),
      );
      HeroTrailerBackdrop backdrop() =>
          tester.widget(find.byType(HeroTrailerBackdrop));
      await tester.pumpWidget(layer(first, loading));
      final original = tester.element(find.byType(HeroTrailerBackdrop));
      expect(first.isObserved, isTrue);
      expect(loading.isObserved, isTrue);
      expect(takeover.isObserved, isFalse);
      expect(backdrop().audioUrl, streams.audioUrl);
      expect(backdrop().startDelay, const Duration(milliseconds: 300));
      expect(backdrop().ambientVolume, 25);
      expect(backdrop().live, isFalse);
      backdrop().onPlayingChanged!(true);
      await tester.pump();
      expect(playing, [true]);
      expect(
        tester
            .widget<HomeHeroAmbientChip>(find.byType(HomeHeroAmbientChip))
            .visible,
        isTrue,
      );
      await tester.pumpWidget(layer(second, nextLoading, bleed: true));
      expect(tester.element(find.byType(HeroTrailerBackdrop)), same(original));
      expect(first.isObserved, isFalse);
      expect(loading.isObserved, isFalse);
      expect(second.isObserved, isTrue);
      expect(nextLoading.isObserved, isTrue);
      expect(
        tester
            .widget<HomeHeroAmbientChip>(find.byType(HomeHeroAmbientChip))
            .visible,
        isFalse,
      );
      first.value = null;
      loading.value = true;
      await tester.pump();
      expect(tester.element(find.byType(HeroTrailerBackdrop)), same(original));
      second.value = const YoutubeResolvedStreams(
        playUrl: 'https://fixture.invalid/b',
      );
      await tester.pump();
      expect(
        tester.element(find.byType(HeroTrailerBackdrop)),
        isNot(same(original)),
      );
      second.value = null;
      await tester.pump();
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      expect(
        tester
            .widget<HomeHeroTrailerLoadingPill>(
              find.byType(HomeHeroTrailerLoadingPill),
            )
            .visible,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      expect(second.isObserved, isFalse);
      expect(nextLoading.isObserved, isFalse);
      expect(takeover.value, 0.2);
      second.value = streams;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV and touch status corners retain geometry and pointer pass-through',
    (tester) async {
      final streams = ObservedValue<YoutubeResolvedStreams?>(null);
      final loading = ObservedValue(true);
      addTearDown(streams.dispose);
      addTearDown(loading.dispose);
      var taps = 0;
      Widget layer(bool tv, bool bleed) => host(
        Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            HomeHeroTrailerLayer(
              trailer: streams,
              loading: loading,
              heroHeight: 300,
              volume: 0,
              isTelevision: tv,
              fullBleed: bleed,
            ),
          ],
        ),
      );
      await tester.pumpWidget(layer(true, false));
      expect(
        tester.getRect(find.byType(ClipRect)),
        rectMoreOrLessEquals(const Rect.fromLTWH(352, 0, 448, 300)),
      );
      var pill = tester.getRect(find.byType(HomeHeroTrailerLoadingPill));
      expect(pill.top, 16);
      expect(pill.right, closeTo(778, 0.001));
      await tester.tapAt(const Offset(600, 100));
      expect(taps, 1);
      await tester.pumpWidget(layer(false, true));
      expect(
        tester.getRect(find.byType(ClipRect)),
        rectMoreOrLessEquals(const Rect.fromLTWH(0, 0, 800, 600)),
      );
      pill = tester.getRect(find.byType(HomeHeroTrailerLoadingPill));
      expect(pill.top, 40);
      expect(
        pill.right,
        closeTo(
          800 -
              SpotlightSearchButton.rightInset -
              SpotlightSearchButton.diameter -
              12,
          0.001,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
