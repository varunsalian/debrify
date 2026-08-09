import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_light.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/premium_looks.dart';
import 'package:debrify/theme/widgets/glass_surface.dart';
import 'package:debrify/theme/widgets/themed_skeleton.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// The adoption wave's blast radius, pinned.
///
/// Every widget below replaced a hand-rolled decoration at a live site. The
/// question that matters is not "does the new widget work" — it is "does it
/// paint what the site painted before, under Debrify Classic". A drift here is
/// a legacy break at ten sheets and five heroes at once.
void main() {
  Widget host(AppTheme theme, Widget child, {DetailTheme? detail}) =>
      MaterialApp(
        home: AppThemeScope(
          theme: theme,
          child: detail == null
              ? child
              : DetailThemeScope(theme: detail, child: child),
        ),
      );

  group('GlassSurface under legacy is a plain filled panel', () {
    testWidgets('a site that never blurred still does not', (tester) async {
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const GlassSurface(child: SizedBox(width: 100, height: 40)),
        ),
      );
      // No `sigma`, so no blur — and the filter widget is never built at all,
      // so no saveLayer is allocated either.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a site that DID blur keeps its blur under Classic',
        (tester) async {
      // The trap this catches: `SurfaceTokens.legacy` is `fill`, so a naive
      // "blur only under a glass look" rule silently deletes a real blur from
      // ten phone sheets the moment they adopt this widget. Classic states no
      // surface opinion; the site's own behaviour is what must survive.
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const GlassSurface(
            sigma: 18,
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      final f = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(f.filter.toString(), contains('18'));
    });

    testWidgets('all twenty old cores keep it too', (tester) async {
      for (final core in DetailThemes.all) {
        await tester.pumpWidget(
          host(
            AppTheme.fromDetail(core),
            const GlassSurface(
              sigma: 18,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsOneWidget, reason: core.id);
      }
    });

    testWidgets('a look that CHOSE a plain fill gets no blur', (tester) async {
      // Warm Room states `fill`. Stating it is a decision; inheriting legacy
      // is not.
      final theme = PremiumLooks.hearth.build();
      expect(theme.surface.base, SeparationModel.fill);
      expect(theme.surface.isNeutral, isFalse);
      await tester.pumpWidget(
        host(
          theme,
          const GlassSurface(
            sigma: 18,
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('the blurred tint is used only when a blur is painted',
        (tester) async {
      const opaque = Color(0xFF12141D);
      const veil = Color(0xF212141D);
      for (final (sigma, want) in [(18.0, veil), (null, opaque)]) {
        await tester.pumpWidget(
          host(
            AppThemes.legacy,
            GlassSurface(
              sigma: sigma,
              tint: opaque,
              blurTint: veil,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        );
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(GlassSurface),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect((box.decoration as BoxDecoration).color, want,
            reason: 'sigma $sigma');
      }
    });

    testWidgets('the fill is the theme pane and the hairline is 1px',
        (tester) async {
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const GlassSurface(child: SizedBox(width: 100, height: 40)),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, AppThemes.legacy.core.pane);
      expect(d.border, isNotNull);
      expect((d.border! as Border).top.width, 1);
      // The sheen must not be in this decoration: `BoxDecoration` builds ONE
      // paint, and a gradient replaces the shader that `color` set — putting
      // the sheen here would throw the fill away on every look that has one.
      expect(d.gradient, isNull);
    });

    testWidgets('a half-pixel hairline stays half a pixel', (tester) async {
      // Two playlist sheets shipped a 0.5px edge; the widget's default 1 would
      // have doubled it, which is a visible change under Classic.
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const GlassSurface(
            borderWidth: 0.5,
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(((box.decoration as BoxDecoration).border! as Border).top.width,
          0.5);
    });

    testWidgets('the child is inset by the border, as Container did',
        (tester) async {
      // `Container` reports `border.dimensions` as padding; `DecoratedBox`
      // does not. A converted site whose content shifted by its own hairline
      // would be a legacy break.
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const GlassSurface(
            padding: EdgeInsets.all(10),
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      final pad = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(GlassSurface),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(pad.padding, const EdgeInsets.all(10).add(const EdgeInsets.all(1)));
    });

    testWidgets('a glass look off TV does build the filter', (tester) async {
      await tester.pumpWidget(
        host(
          PremiumLooks.glass.build(),
          const GlassSurface(child: SizedBox(width: 100, height: 40)),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('a sheen look keeps its fill', (tester) async {
      final theme = PremiumLooks.glass.build();
      // Guard the premise: if Obsidian Glass ever loses its sheen this test
      // silently stops testing anything.
      expect(theme.surface.sheen, greaterThan(0));
      await tester.pumpWidget(
        host(theme, const GlassSurface(child: SizedBox(width: 100, height: 40))),
      );
      final outer = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final d = outer.decoration as BoxDecoration;
      expect(d.color, isNotNull);
      expect(d.color!.a, greaterThan(0));
    });
  });

  group('DetailScrim under a bottom-gradient look is the shipped gradient', () {
    testWidgets('identity', (tester) async {
      const core = DetailThemes.signal;
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const SizedBox(width: 300, height: 200, child: DetailScrim()),
          detail: core,
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(DetailScrim),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final want = detailIdentityScrim(core);
      final got = (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(got.colors, want.colors);
      expect(got.stops, want.stops);
      expect(got.begin, want.begin);
      expect(got.end, want.end);
    });

    testWidgets('stage', (tester) async {
      const core = DetailThemes.signal;
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const SizedBox(
            width: 300,
            height: 200,
            child: DetailScrim(kind: DetailScrimKind.stage),
          ),
          detail: core,
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(DetailScrim),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final want = detailStageScrim(core);
      final got = (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(got.colors, want.colors);
      expect(got.stops, want.stops);
    });

    testWidgets('every one of the twenty old cores still gets its gradient',
        (tester) async {
      // The five layouts that adopted this widget render under any detail
      // theme, and all twenty resolve to `bottomGradient` because
      // `LightTokens.legacy` is what `fromDetail` hands them.
      for (final core in DetailThemes.all) {
        await tester.pumpWidget(
          host(
            AppTheme.fromDetail(core),
            const SizedBox(width: 300, height: 200, child: DetailScrim()),
            detail: core,
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing, reason: core.id);
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(DetailScrim),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          ((box.decoration as BoxDecoration).gradient! as LinearGradient).colors,
          detailIdentityScrim(core).colors,
          reason: core.id,
        );
      }
    });

    testWidgets('a plate look paints a slab, not a fade', (tester) async {
      final theme = PremiumLooks.hearth.build();
      expect(theme.light.scrim, ScrimStyle.plate);
      await tester.pumpWidget(
        host(
          theme,
          const SizedBox(width: 300, height: 200, child: DetailScrim()),
          detail: theme.core,
        ),
      );
      expect(find.byType(ColoredBox), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(DetailScrim),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });
  });

  group('ThemedSkeleton', () {
    testWidgets('under Classic it runs ONE ticker, not two', (tester) async {
      // It delegates to `Shimmer`, which owns a repeating controller of its
      // own; keeping a second one alive here would double the tickers behind
      // every placeholder on screen to paint one animation.
      await tester.pumpWidget(
        host(AppThemes.legacy, const ThemedSkeleton(width: 80, height: 12)),
      );
      final states = tester.stateList(find.byType(ThemedSkeleton)).toList();
      expect(states, hasLength(1));
      expect((states.single as dynamic).debugTickerCount, 0);
    });

    testWidgets('under Classic it IS the shipped Shimmer', (tester) async {
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const ThemedSkeleton(width: 80, height: 12),
        ),
      );
      expect(find.byType(Shimmer), findsOneWidget);
      final s = tester.widget<Shimmer>(find.byType(Shimmer));
      expect(s.base, const Color(0xFF223049));
      expect(s.highlight, const Color(0xFF2A3A55));
    });

    testWidgets('an animated style does not throw on its first frame',
        (tester) async {
      // The controller must have a duration BEFORE `repeat()`; without one
      // Flutter raises "no default duration" the moment it is asked to run.
      await tester.pumpWidget(
        host(
          PremiumLooks.glass.build(),
          const ThemedSkeleton(width: 80, height: 12),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a snap look gets a static block, and it does not animate',
        (tester) async {
      final theme = PremiumLooks.console.build();
      await tester.pumpWidget(
        host(theme, const ThemedSkeleton(width: 80, height: 12)),
      );
      expect(find.byType(Shimmer), findsNothing);
      // `pumpAndSettle` is the assertion: a repeating controller never
      // settles, so reaching this line proves nothing is looping.
      await tester.pumpAndSettle();
    });
  });

  group('the vocabulary widgets are cheap when the look has no opinion', () {
    testWidgets('legacy allocates no image filter anywhere in this set',
        (tester) async {
      await tester.pumpWidget(
        host(
          AppThemes.legacy,
          const Column(
            children: [
              GlassSurface(child: SizedBox(width: 60, height: 20)),
              SizedBox(width: 60, height: 20, child: DetailScrim()),
            ],
          ),
          detail: DetailThemes.signal,
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
