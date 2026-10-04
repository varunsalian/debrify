import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';

class SpotlightBoardHeroForeground {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardHeroForeground(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardSections get _sections => _deps.sections;
  Widget heroForeground(
    SpotlightBoardMetrics m,
    StremioMeta item,
    double heroH,
  ) {
    final flip = _sections.ambient.flip;
    // TV keeps the shipped absolutes: on a ~960×540 canvas, 128 is the
    // proportional shelf overlap (88) plus 40 of clearance, and 92 is the
    // overlap plus 4. On touch the SAME structure is derived instead of
    // fixed, because the overlap is a FRACTION of the hero and the hero is a
    // full tablet viewport — at heroH≈1024 the overlap alone is ~167, so the
    // absolute 128 parked the identity UNDER the first shelf's header (the
    // observed collision), with the dots on the posters below it.
    final overlap = heroH * SpotlightBoardConstantsState.shelfOverlapFraction;
    final identityBottom = view.dpad ? 128.0 : overlap + 40 * m.k;
    final dotsBottom = view.dpad ? 92.0 : overlap + 4 * m.k;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: flip ? null : m.gutter,
          right: flip ? m.gutter : null,
          bottom: identityBottom,
          width: m.w * (820 / 1920),
          child: _sections.heroIdentity.identity(item, flip, m),
        ),
        if (view.hero.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: dotsBottom,
            // Tappable wherever there is no remote — desktop and tablet run
            // this wide layout too. On TV the padding-free dots render
            // byte-identically to HEAD.
            child: _sections.heroIdentity.dots(tappable: !view.dpad),
          ),
        // The hero's focusable surface. IgnorePointer-free and zero-sized in
        // paint terms: the hero shows focus through the page, not through a
        // ring on a full-screen box.
        // `skipTraversal`: the hero is reached ONLY by the explicit UP
        // handler. Left findable, a geometric LEFT/UP search from the first
        // shelves lands on it — which is why LEFT from row 1 and 2 went to the
        // hero instead of falling through to the sidebar. It sits at x=0, so
        // it is the nearest thing to the left of everything.
        Positioned(
          left: 0,
          top: 0,
          child: Focus(
            focusNode: view.heroNode,
            skipTraversal: true,
            descendantsAreTraversable: false,
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
