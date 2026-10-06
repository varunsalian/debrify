import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_tuner_fixture.dart';

class HeldImageCompleter extends ImageStreamCompleter {
  final listeners = <ImageStreamListener>[];
  @override
  void addListener(ImageStreamListener listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }

  void release() {
    for (final listener in listeners.toList()) {
      removeListener(listener);
    }
  }
}

class RecordingTunerImageCache extends ImageCache {
  final keys = <Object>[];
  final completers = <Object, HeldImageCompleter>{};
  @override
  ImageStreamCompleter? putIfAbsent(
    Object key,
    ImageStreamCompleter Function() loader, {
    ImageErrorListener? onError,
  }) {
    keys.add(key);
    // Resolving eagerly is safe because the loader is deliberately never called.
    return completers.putIfAbsent(key, HeldImageCompleter.new);
  }

  void release() {
    for (final c in completers.values) {
      c.release();
    }
    completers.clear();
    keys.clear();
    clear();
    clearLiveImages();
  }
}

final recordingCache = RecordingTunerImageCache();

class TunerArtworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => recordingCache;
}

Future<Object> expectedKey(String url, int width) => ResizeImage.resizeIfNeeded(
  width,
  null,
  CachedNetworkImageProvider(url),
).obtainKey(ImageConfiguration.empty);
AnimationController textController(WidgetTester tester, Finder stage) {
  final fade = tester.widget<FadeTransition>(
    find.descendant(of: stage, matching: find.byType(FadeTransition)).first,
  );
  return (fade.opacity as CurvedAnimation).parent as AnimationController;
}

void main() {
  TunerArtworkBinding();
  tearDown(recordingCache.release);
  for (final (tv, hidden, width, posterWidth) in [
    (true, false, HomeTheme.heroBackdropCacheWidthTv, 280),
    (true, true, 96, 16),
    (false, false, HomeTheme.heroBackdropCacheWidth, 280),
    (false, true, 480, 200),
  ]) {
    testWidgets(
      'artwork tv=$tv hidden=$hidden keeps decode, fade, blur, overlay and adjacent cache keys',
      (tester) async {
        await tunerCase(tester, (f) async {
          f.television = tv;
          f.hideNowPlaying = hidden;
          f.autoRefresh = true;
          f.platform = TargetPlatform.macOS;
          await f.mount(tester);
          final stage = f.stages.first;
          final art = tester.widget<CachedNetworkImage>(
            find
                .descendant(
                  of: stage,
                  matching: find.byType(CachedNetworkImage),
                )
                .first,
          );
          expect(art.memCacheWidth, width, reason: 'Stage decode width');
          expect(
            art.fadeInDuration,
            tv ? Duration.zero : const Duration(milliseconds: 500),
          );
          expect(
            art.fadeOutDuration,
            tv ? Duration.zero : const Duration(milliseconds: 1000),
          );
          final cardArt = tester.widget<CachedNetworkImage>(
            find
                .descendant(
                  of: f.card(0),
                  matching: find.byType(CachedNetworkImage),
                )
                .first,
          );
          expect(
            cardArt.memCacheWidth,
            posterWidth,
            reason: 'dial decode width',
          );
          expect(
            find.descendant(of: stage, matching: find.byType(ImageFiltered)),
            tv || !hidden ? findsNothing : findsOneWidget,
            reason: 'Stage gaussian is limited to hidden non-TV',
          );
          expect(
            find.descendant(of: stage, matching: find.byType(ColorFiltered)),
            tv ? findsNothing : findsOneWidget,
            reason: 'TV uses plain overlay instead of darken filter',
          );
          if (tv) {
            expect(
              find.descendant(
                of: stage,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Container &&
                      w.color == Colors.black.withValues(alpha: 0.12),
                ),
              ),
              findsOneWidget,
              reason: 'TV backdrop overlay is 12% black',
            );
          }
          expect(
            find.descendant(
              of: f.card(0),
              matching: find.byType(ImageFiltered),
            ),
            hidden && !tv ? findsOneWidget : findsNothing,
          );
          await f.focus(tester, 1);
          recordingCache.keys.clear();
          await tester.pump(const Duration(milliseconds: 180));
          final left = await expectedKey(
            'https://artwork.test/backdrop-channel-0.png',
            width,
          );
          final right = await expectedKey(
            'https://artwork.test/backdrop-channel-2.png',
            width,
          );
          expect(
            recordingCache.keys,
            containsAll([left, right]),
            reason: 'both adjacent warm-ups match Stage decode keys',
          );
          expect(
            recordingCache.keys,
            isNot(
              contains(
                await expectedKey(
                  'https://artwork.test/backdrop-channel-3.png',
                  width,
                ),
              ),
            ),
            reason: 'warm-up never reaches distance two',
          );
          if (tv && hidden) {
            expect(
              recordingCache.keys,
              isNot(
                contains(
                  await expectedKey(
                    'https://artwork.test/backdrop-channel-0.png',
                    480,
                  ),
                ),
              ),
              reason: 'TV hidden never warms a second 480px decode',
            );
          }
          final scale = tester.widget<AnimatedScale>(
            find
                .descendant(of: f.card(1), matching: find.byType(AnimatedScale))
                .first,
          );
          expect(
            (scale.duration, scale.curve, scale.scale),
            (const Duration(milliseconds: 140), Curves.easeOutCubic, 1.10),
          );
          final decorations = tester
              .widgetList<Container>(
                find.descendant(
                  of: f.card(1),
                  matching: find.byType(Container),
                ),
              )
              .map((w) => w.decoration)
              .whereType<BoxDecoration>();
          expect(
            decorations.any((d) => d.boxShadow?.isNotEmpty ?? false),
            !tv,
            reason: 'TV focused card omits blurred bloom',
          );
          final kenBuilders = tester
              .widgetList<AnimatedBuilder>(
                find.descendant(
                  of: stage,
                  matching: find.byType(AnimatedBuilder),
                ),
              )
              .where((w) => w.animation is AnimationController)
              .toList();
          expect(
            kenBuilders,
            hidden ? isEmpty : hasLength(1),
            reason: 'blur mode omits backdrop animation boundary',
          );
          if (!hidden) {
            final ken = kenBuilders.single.animation as AnimationController;
            expect(ken.duration, const Duration(seconds: 22));
            expect(ken.isAnimating, !tv, reason: 'Ken Burns never runs on TV');
            expect(
              find.ancestor(
                of: find.byWidget(kenBuilders.single),
                matching: find.byType(ClipRect),
              ),
              findsWidgets,
            );
            expect(
              find.ancestor(
                of: find.byWidget(kenBuilders.single),
                matching: find.byType(RepaintBoundary),
              ),
              findsWidgets,
            );
          }
        }, artwork: true);
      },
    );
  }
  testWidgets(
    'text starts settled, forwards on item change, and reduced motion snaps',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.television = false;
        f.platform = TargetPlatform.macOS;
        f.autoRefresh = true;
        await f.mount(tester);
        final text = textController(tester, f.stages.first);
        expect(text.value, 1, reason: 'first text build is already settled');
        expect(text.duration, const Duration(milliseconds: 260));
        await f.focus(tester, 1);
        await tester.pump(const Duration(milliseconds: 180));
        expect(text.value, 0, reason: 'channel change forwards text from zero');
        await tester.pump(const Duration(milliseconds: 130));
        expect(text.value, inExclusiveRange(0, 1));
        await tester.pump(const Duration(milliseconds: 130));
        expect(text.value, 1);
        f.service.now['channel-1'] = tunerPlaying('replacement');
        await f.refresh(tester);
        expect(text.value, 0, reason: 'item change forwards text from zero');
        f.disableAnimations = true;
        await f.refresh(tester);
        expect(
          text.value,
          1,
          reason: 'reduced motion settles text immediately',
        );
        await f.focus(tester, 2);
        await tester.pump(const Duration(milliseconds: 180));
        expect(text.value, 1, reason: 'reduced motion skips new cascade');
      }, artwork: true);
    },
  );
  testWidgets(
    'Stage content reads its own theme element under a nested surface boundary',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        final stage = tester.widget(f.stages.first);
        final inner = PremiumLooks.byId('console')!.build();
        await tester.pumpWidget(
          f.host(
            child: AppThemeScope(theme: inner, child: stage),
          ),
        );
        await tester.pump();
        final title = tester.widget<Text>(find.text('Broadcast channel-0'));
        expect(
          title.style!.color,
          inner.core.tx,
          reason: 'bound content uses Stage element theme',
        );
        final background = tester.widget<DecoratedBox>(
          find
              .descendant(of: f.stages, matching: find.byType(DecoratedBox))
              .first,
        );
        expect((background.decoration as BoxDecoration).color, inner.home.bg);
      });
    },
  );
}
