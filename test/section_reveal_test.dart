import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/section_reveal.dart';

/// [SectionReveal]'s viewport-triggered mode, and its one non-negotiable
/// property: **a section must never be left invisible.**
///
/// Every branch that cannot answer "am I on screen yet" has to resolve toward
/// showing the section, because the cost of guessing wrong in that direction
/// is one animation nobody watched — while guessing wrong in the other leaves
/// a hole in the page that no later event can fill.
AppTheme _theme({EntranceStyle entrance = EntranceStyle.fadeUp}) =>
    AppTheme.fromDetail(
      DetailThemes.byId('signal'),
      motion:
          MotionTokens.of(MotionCharacter.settle).copyWith(entrance: entrance),
    );

/// A page whose leading spacer can shrink — the shape of a season swap, where
/// a tall episode rail is replaced by a one-line note and every section below
/// jumps up the page without the scroll offset moving at all.
Widget _host({
  required double spacer,
  AppTheme? theme,
  bool alreadyRevealed = false,
  VoidCallback? onRevealed,
  bool inScrollable = true,
}) {
  final section = SectionReveal(
    startWhenVisible: true,
    scaleFrom: 0.98,
    alreadyRevealed: alreadyRevealed,
    onRevealed: onRevealed,
    child: const SizedBox(height: 200, child: Text('SECTION')),
  );
  return MaterialApp(
    home: AppThemeScope(
      theme: theme ?? _theme(),
      child: Scaffold(
        body: inScrollable
            ? ListView(
                // Builds the section well below the fold, the way the Showcase
                // page's own list does — which is the condition a mount
                // trigger gets wrong.
                scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                children: [SizedBox(height: spacer), section],
              )
            : section,
      ),
    ),
  );
}

/// The reveal's own opacity, or null when it mounted no wrapper.
///
/// Scoped UNDER [SectionReveal.activeKey] rather than taking the first
/// `FadeTransition` in the tree: MaterialApp's page transition is itself a
/// fade sitting above everything here, so an unscoped finder reads 1.0 no
/// matter what the reveal is doing — and every assertion expecting 1 passes
/// without testing anything.
double? _opacity(WidgetTester t) {
  final fades = t.widgetList<FadeTransition>(
    find.descendant(
      of: find.byKey(SectionReveal.activeKey, skipOffstage: false),
      matching: find.byType(FadeTransition, skipOffstage: false),
      skipOffstage: false,
    ),
  );
  return fades.isEmpty ? null : fades.first.opacity.value;
}

void main() {
  testWidgets('a section below the fold waits', (tester) async {
    await tester.pumpWidget(_host(spacer: 2000));
    await tester.pumpAndSettle();

    expect(_opacity(tester), 0);
  });

  testWidgets('a section on screen at rest arrives without any scroll',
      (tester) async {
    await tester.pumpWidget(_host(spacer: 10));
    await tester.pumpAndSettle();

    expect(_opacity(tester), 1);
  });

  testWidgets('a section pushed into view by content SHRINKING above it '
      'still arrives', (tester) async {
    await tester.pumpWidget(_host(spacer: 2000));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0, reason: 'below the fold to begin with');

    // The regression. The scroll offset does not move — only the content above
    // gets shorter, which Flutter reports as a metrics change and never as a
    // pixel notification. A reveal listening for pixels alone would sit at
    // opacity 0 here with nothing left that could ever wake it.
    await tester.pumpWidget(_host(spacer: 10));
    await tester.pumpAndSettle();

    expect(_opacity(tester), 1);
  });

  testWidgets('a section outside any scrollable arrives immediately',
      (tester) async {
    await tester.pumpWidget(_host(spacer: 0, inScrollable: false));
    await tester.pumpAndSettle();

    expect(_opacity(tester), 1,
        reason: 'there is no "scrolls into view" to wait for');
  });

  testWidgets('alreadyRevealed starts at rest, with nothing to play',
      (tester) async {
    await tester.pumpWidget(_host(spacer: 2000, alreadyRevealed: true));
    await tester.pump();

    // Below the fold, and fully visible anyway: this is how a caller replays
    // the memory of a reveal whose state the lazy list has since collected.
    expect(_opacity(tester), 1);
  });

  testWidgets('the arrival is reported once, so a caller can remember it',
      (tester) async {
    var revealed = 0;
    await tester.pumpWidget(_host(spacer: 10, onRevealed: () => revealed++));
    await tester.pumpAndSettle();

    expect(revealed, 1);
  });

  testWidgets('a look with no entrance token mounts no wrapper at all',
      (tester) async {
    await tester.pumpWidget(
      _host(spacer: 2000, theme: _theme(entrance: EntranceStyle.none)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(SectionReveal.activeKey, skipOffstage: false),
        findsNothing);
    expect(find.text('SECTION', skipOffstage: false), findsOneWidget);
  });

  testWidgets('legacy gets no viewport reveal — its pin protects only the '
      'mount animation it already shipped', (tester) async {
    await tester.pumpWidget(_host(spacer: 2000, theme: AppThemes.legacy));
    await tester.pumpAndSettle();

    // Classic is deliberately unthemed, and its own token says `none`. Reading
    // the legacy pin here would invent an entrance it has never had — and one
    // no token could switch off, since `none` is exactly what the pin ignores.
    expect(find.byKey(SectionReveal.activeKey, skipOffstage: false),
        findsNothing);
  });
}
