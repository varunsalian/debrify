import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/desktop_pill_nav.dart';
import 'package:debrify/widgets/desktop_sidebar_nav.dart';

/// The desktop 'pill' is the wide-layout sibling of the TV rail's pill: no
/// rail, content full-bleed, a capsule that opens the menu as an overlay.
/// The load-bearing guarantees are hit-testing ones — the closed layer must
/// not eat the page's pointers, and every open path must have a close path
/// (pick, scrim, Escape).
void main() {
  Widget host({
    required ValueChanged<int> onTap,
    VoidCallback? onBehindTap,
    int index = 0,
  }) =>
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Stack(
            children: [
              // Stands in for the page: proves pointers pass the closed layer.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBehindTap,
                ),
              ),
              Positioned.fill(
                child: DesktopPillNav(
                  currentIndex: index,
                  entries: const [
                    DesktopNavEntry(Icons.home, 'Home', 'main'),
                    DesktopNavEntry(Icons.explore, 'Discover', 'main'),
                    DesktopNavEntry(Icons.tv, 'IPTV', 'live'),
                  ],
                  onTap: onTap,
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('capsule shows the current tab and opens the panel',
      (tester) async {
    await tester.pumpWidget(host(onTap: (_) {}));
    await tester.pumpAndSettle();

    expect(find.byKey(DesktopPillNav.pillKey), findsOneWidget);
    // Panel entries are mounted (for the slide animation) but off-stage
    // behind an IgnorePointer until opened — the menu labels and the pill
    // both carry 'Home', so assert via the panel's second entry.
    await tester.tap(find.byKey(DesktopPillNav.pillKey));
    await tester.pumpAndSettle();
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('IPTV'), findsOneWidget);
  });

  testWidgets('picking an entry reports its index and closes the panel',
      (tester) async {
    int? picked;
    await tester.pumpWidget(host(onTap: (i) => picked = i));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DesktopPillNav.pillKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(picked, 1);
    // Closed again: the scrim is inert, so a tap in the page area reaches
    // the page (verified precisely in the hit-test case below).
    final scrim = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(DesktopPillNav.scrimKey),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(scrim.ignoring, isTrue);
  });

  testWidgets('scrim click and Escape both close', (tester) async {
    await tester.pumpWidget(host(onTap: (_) {}));
    await tester.pumpAndSettle();

    // Scrim path.
    await tester.tap(find.byKey(DesktopPillNav.pillKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 300)); // page area = scrim when open
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedSlide>(
            find.ancestor(
              of: find.byKey(DesktopPillNav.panelKey),
              matching: find.byType(AnimatedSlide),
            ),
          )
          .offset,
      isNot(Offset.zero),
    );

    // Escape path.
    await tester.tap(find.byKey(DesktopPillNav.pillKey));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedSlide>(
            find.ancestor(
              of: find.byKey(DesktopPillNav.panelKey),
              matching: find.byType(AnimatedSlide),
            ),
          )
          .offset,
      isNot(Offset.zero),
    );
  });

  testWidgets('closed layer does not eat the page under it', (tester) async {
    var behindTaps = 0;
    await tester.pumpWidget(
      host(onTap: (_) {}, onBehindTap: () => behindTaps++),
    );
    await tester.pumpAndSettle();

    // Anywhere that is not the capsule belongs to the page.
    await tester.tapAt(const Offset(700, 300));
    expect(behindTaps, 1);

    // While OPEN the scrim owns that same point.
    await tester.tap(find.byKey(DesktopPillNav.pillKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 300)); // closes the panel
    // Mid-fade the scrim must STILL block — a quick second click during the
    // 200ms close animation must not reach the page.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(700, 300));
    expect(behindTaps, 1);
    // Once the fade lands, the page owns its pointers again.
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 300));
    expect(behindTaps, 2);
  });
}
