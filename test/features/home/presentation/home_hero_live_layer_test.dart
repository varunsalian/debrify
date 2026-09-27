import 'package:debrify/features/home/presentation/home_hero_live_layer.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

Widget host(Widget child) => MaterialApp(
  home: AppThemeScope(theme: AppThemes.legacy, child: child),
);
IptvChannel channel(String key) => IptvChannel(name: key, url: key);

void main() {
  testWidgets('borrowed signals switch subscriptions and detach on removal', (
    tester,
  ) async {
    final first = ObservedValue<IptvChannel?>(null);
    final firstUrl = ObservedValue<String?>(null);
    final next = ObservedValue<IptvChannel?>(channel('direct'));
    final nextUrl = ObservedValue<String?>(null);
    for (final value in [first, firstUrl, next, nextUrl]) {
      addTearDown(value.dispose);
    }
    Widget layer(ObservedValue<IptvChannel?> c, ObservedValue<String?> u) =>
        host(
          HomeHeroLiveLayer(
            channel: c,
            streamUrl: u,
            isAddonChannel: (_) => false,
            heroHeight: 300,
            volume: 0,
          ),
        );
    await tester.pumpWidget(layer(first, firstUrl));
    expect(first.isObserved, isTrue);
    expect(firstUrl.isObserved, isTrue);
    expect(find.text('TUNING'), findsNothing);
    await tester.pumpWidget(layer(next, nextUrl));
    expect(first.isObserved, isFalse);
    expect(firstUrl.isObserved, isFalse);
    expect(next.isObserved, isTrue);
    expect(nextUrl.isObserved, isTrue);
    expect(find.text('TUNING'), findsOneWidget);
    first.value = channel('obsolete');
    firstUrl.value = 'obsolete';
    await tester.pump();
    expect(find.byType(HeroTrailerBackdrop), findsNothing);
    next.value = null;
    await tester.pump();
    expect(find.text('TUNING'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(next.isObserved, isFalse);
    expect(nextUrl.isObserved, isFalse);
    next.value = channel('after disposal');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same URL retains backdrop while fallback replaces its identity',
    (tester) async {
      final selected = ObservedValue<IptvChannel?>(channel('addon:a'));
      final url = ObservedValue<String?>('https://fixture.invalid/a');
      addTearDown(selected.dispose);
      addTearDown(url.dispose);
      final playing = <bool>[];
      var failures = 0;
      Widget layer({bool fullBleed = false, double volume = 0}) => host(
        HomeHeroLiveLayer(
          channel: selected,
          streamUrl: url,
          isAddonChannel: (key) => key.startsWith('addon:'),
          heroHeight: 300,
          volume: volume,
          fullBleed: fullBleed,
          onPlayingChanged: playing.add,
          onPlaybackFailed: () => failures++,
        ),
      );
      HeroTrailerBackdrop backdrop() =>
          tester.widget(find.byType(HeroTrailerBackdrop));
      await tester.pumpWidget(layer());
      final original = tester.element(find.byType(HeroTrailerBackdrop));
      expect(backdrop().live, isTrue);
      expect(backdrop().enabled, isTrue);
      expect(backdrop().startDelay, const Duration(milliseconds: 300));
      expect(backdrop().firstFrameTimeout, const Duration(seconds: 12));
      expect(find.text('TUNING'), findsOneWidget);
      backdrop().onPlayingChanged!(true);
      await tester.pump();
      expect(playing, [true]);
      expect(find.text('LIVE'), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      backdrop().onPlaybackFailed!();
      expect(failures, 1);
      await tester.pumpWidget(layer(fullBleed: true, volume: 42));
      expect(tester.element(find.byType(HeroTrailerBackdrop)), same(original));
      expect(backdrop().ambientVolume, 42);
      selected.value = channel('direct');
      await tester.pump();
      expect(tester.element(find.byType(HeroTrailerBackdrop)), same(original));
      expect(backdrop().firstFrameTimeout, isNull);
      url.value = 'https://fixture.invalid/fallback';
      await tester.pump();
      expect(
        tester.element(find.byType(HeroTrailerBackdrop)),
        isNot(same(original)),
      );
      expect(find.text('TUNING'), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      url.value = null;
      await tester.pump();
      expect(find.byType(HeroTrailerBackdrop), findsNothing);
      expect(find.text('TUNING'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'boxed and full-bleed geometry keep the channel floor noninteractive',
    (tester) async {
      final selected = ObservedValue<IptvChannel?>(channel('direct'));
      final url = ObservedValue<String?>(null);
      addTearDown(selected.dispose);
      addTearDown(url.dispose);
      var taps = 0;
      Widget layer(bool bleed, double height) => host(
        Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            HomeHeroLiveLayer(
              channel: selected,
              streamUrl: url,
              isAddonChannel: (_) => false,
              heroHeight: height,
              volume: 0,
              fullBleed: bleed,
            ),
          ],
        ),
      );
      await tester.pumpWidget(layer(false, 300));
      expect(
        tester.getRect(find.byType(ClipRect)),
        rectMoreOrLessEquals(const Rect.fromLTWH(352, 0, 448, 300)),
      );
      expect(find.byIcon(Icons.live_tv_rounded), findsOneWidget);
      await tester.tapAt(const Offset(600, 100));
      expect(taps, 1);
      await tester.pumpWidget(layer(true, 300));
      expect(
        tester.getRect(find.byType(ClipRect)),
        rectMoreOrLessEquals(const Rect.fromLTWH(0, 0, 800, 600)),
      );
      await tester.pumpWidget(layer(false, 100));
      expect(find.byType(ClipRect), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
