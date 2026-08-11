import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/settings/tv_sidebar_style_page.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_sidebar_nav.dart';

/// 'pill' is the first sidebar style that changes LAYOUT, not just chrome.
///
/// Five styles share `collapsedWidth` precisely so switching one never
/// re-flows content; this one draws no rail at rest and reclaims the gutter.
/// The failure mode is silent — a host that keeps hardcoding 64 leaves a dead
/// margin down the left of every TV screen and nothing throws.
Widget host(String style, {EdgeInsets pad = EdgeInsets.zero, int index = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(padding: pad),
        child: AppThemeScope(
          theme: AppThemes.legacy,
          child: Stack(children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: TvSidebarNav(
                navStyle: style,
                currentIndex: index,
                items: const [
                  TvNavItem(Icons.search, 'Search'),
                  TvNavItem(Icons.home, 'Home'),
                ],
                onTap: (_) {},
              ),
            ),
          ]),
        ),
      ),
    );


void main() {
  group('content inset follows the style', () {
    test('every rail style reserves the collapsed rail', () {
      for (final s in ['ghost', 'classic', 'island', 'marquee', 'badge']) {
        expect(
          TvSidebarNav.contentInsetFor(s),
          TvSidebarNav.collapsedWidth,
          reason: '$s draws a rail at rest, so content must clear it',
        );
      }
    });

    test('pill reserves nothing', () {
      expect(TvSidebarNav.contentInsetFor('pill'), 0.0);
    });

    test('an unknown style falls back to reserving the rail', () {
      // The safe direction: a stale or newer value costs 64px of margin, not
      // content hidden underneath a rail it did not expect.
      expect(
        TvSidebarNav.contentInsetFor('something-newer'),
        TvSidebarNav.collapsedWidth,
      );
    });
  });

  test('the style is offered in the picker', () {
    expect(
      kTvSidebarStyleChoices.map((c) => c.value),
      contains('pill'),
    );
    expect(tvSidebarStyleLabel('pill'), 'Pill');
  });

  testWidgets('pill renders the current tab and nothing else', (t) async {
    await t.pumpWidget(host('pill'));
    await t.pump();
    final inPill = find.descendant(
      of: find.byKey(TvSidebarNav.pillKey),
      matching: find.text('Home'),
    );
    expect(inPill, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(TvSidebarNav.pillKey),
        matching: find.text('Search'),
      ),
      findsNothing,
      reason: 'the capsule names the CURRENT tab only',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('pill clears overscan padding', (t) async {
    await t.pumpWidget(host('pill', pad: const EdgeInsets.all(60)));
    await t.pump();
    final topLeft = t.getTopLeft(find.byKey(TvSidebarNav.pillKey));
    // Flush to the safe area and no further: any extra margin is content the
    // capsule would sit on for no benefit, and any less is clipped bezel.
    expect(topLeft.dx, 60, reason: 'starts exactly at the safe-area edge');
    expect(topLeft.dy, 60, reason: 'starts exactly at the safe-area edge');
  });

  testWidgets('a rail style draws no capsule at all', (t) async {
    await t.pumpWidget(host('ghost'));
    await t.pump();
    expect(find.byKey(TvSidebarNav.pillKey), findsNothing);
    expect(t.takeException(), isNull);
  });
  _autoHide();
  _styleSwitch();
  _edgeGlow();
}

/// The capsule is temporary by design — see `_pillHold`. These pin the part
/// that is easy to regress: that it leaves on its own, and comes back when you
/// arrive somewhere new.
void _autoHide() {
  testWidgets('the capsule hides itself after the hold', (t) async {
    await t.pumpWidget(host('pill'));
    await t.pump();
    expect(find.byKey(TvSidebarNav.pillKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(TvSidebarNav.pillKey),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );

    // Hold is 1s + a 300ms fade; 2s is comfortably past both without
    // pinning the exact numbers.
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(TvSidebarNav.pillKey),
        matching: find.text('Home'),
      ),
      findsNothing,
      reason: 'a permanent label is a permanent collision',
    );
    // ...but the MARK stays. That split is the whole design: the chevron says
    // a menu exists and the icon says where you are, both cheap enough to be
    // permanent; only the name is expensive enough to have to leave.
    expect(
      find.descendant(
        of: find.byKey(TvSidebarNav.pillKey),
        matching: find.byIcon(Icons.chevron_left_rounded),
      ),
      findsOneWidget,
      reason: 'the affordance must outlive the label',
    );
    expect(
      find.descendant(
        of: find.byKey(TvSidebarNav.pillKey),
        matching: find.byIcon(Icons.home),
      ),
      findsOneWidget,
      reason: 'the current tab icon is the permanent orientation cue',
    );
  });

  testWidgets('arriving on a new tab brings it back', (t) async {
    await t.pumpWidget(host('pill'));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();

    // Same widget, different tab — the case a real tab change produces.
    await t.pumpWidget(host('pill', index: 0));
    // Past the fade-IN: the capsule returns over ~220ms, so a single frame
    // would assert against a still-transparent label.
    await t.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byKey(TvSidebarNav.pillKey),
        matching: find.text('Search'),
      ),
      findsOneWidget,
      reason: 'it answers "where am I" on arrival',
    );
  });
}

/// Switching styles at runtime: the controller is lazy, so both directions
/// have to be safe — a stale hold timer must not fire into a style with no
/// capsule, and switching in must build one.
void _styleSwitch() {
  testWidgets('switching pill -> ghost leaves no capsule and no pending work',
      (t) async {
    await t.pumpWidget(host('pill'));
    await t.pump();
    expect(find.byKey(TvSidebarNav.pillKey), findsOneWidget);

    await t.pumpWidget(host('ghost'));
    await t.pump();
    expect(find.byKey(TvSidebarNav.pillKey), findsNothing);
    // The hold timer from the pill era must not throw when it fires here.
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('ghost -> pill builds the controller and announces', (t) async {
    await t.pumpWidget(host('ghost'));
    await t.pump();
    await t.pumpWidget(host('pill'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.descendant(
      of: find.byKey(TvSidebarNav.pillKey),
      matching: find.text('Home')), findsOneWidget);
  });
}

/// The left-edge brighten. Focus geometry, so it is driven through a real
/// focusable rather than by poking the controller.
void _edgeGlow() {
  testWidgets('the mark brightens when focus reaches the left column',
      (t) async {
    final left = FocusNode();
    final right = FocusNode();
    addTearDown(left.dispose);
    addTearDown(right.dispose);

    await t.pumpWidget(MaterialApp(
      home: AppThemeScope(
        theme: AppThemes.legacy,
        child: Stack(children: [
          // Content: one focusable at the edge, one far to the right.
          Positioned(left: 10, top: 300, child: Focus(focusNode: left,
              child: const SizedBox(width: 40, height: 40))),
          Positioned(left: 900, top: 300, child: Focus(focusNode: right,
              child: const SizedBox(width: 40, height: 40))),
          Positioned(left: 0, top: 0, bottom: 0,
            child: TvSidebarNav(navStyle: 'pill', currentIndex: 1,
              items: const [
                TvNavItem(Icons.search, 'Search'),
                TvNavItem(Icons.home, 'Home'),
              ],
              onTap: (_) {})),
        ]),
      ),
    ));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();

    Color chevron() => t
        .widget<Icon>(find.descendant(
          of: find.byKey(TvSidebarNav.pillKey),
          matching: find.byIcon(Icons.chevron_left_rounded),
        ))
        .color!;

    right.requestFocus();
    await t.pumpAndSettle();
    final away = chevron().a;

    left.requestFocus();
    await t.pumpAndSettle();
    final near = chevron().a;

    expect(near, greaterThan(away),
        reason: 'LEFT only opens the menu once focus runs out of content — '
            'the mark should say so at exactly that moment');
  });
}
