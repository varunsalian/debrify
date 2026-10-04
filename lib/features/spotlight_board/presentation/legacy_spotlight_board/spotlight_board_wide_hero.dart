import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:flutter/material.dart';

class SpotlightBoardWideHero {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardWideHero(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;

  /// The TV hero's SCROLLING half: identity, dots, pointer surface, focus
  /// node. The picture it reads against is [_heroBackdrop], pinned behind the
  /// list — split so the text can ride away with the shelves while the art
  /// stays put.
  Widget heroWide(SpotlightBoardMetrics m, double heroH) {
    final item = _sections.heroArt.heroItem;
    if (item == null) return const SizedBox.shrink();
    final wide = _sections.heroForeground.heroForeground(m, item, heroH);
    if (view.dpad) return wide;
    // Desktop and tablet drive the same wide layout by pointer/touch: swipe
    // pages the reel, a tap opens the showcased title — the exact gestures
    // the compact hero has. TV returns the bare stack above, untouched.
    // This surface must live HERE, in the list, not on the backdrop: the
    // Scrollable in front of the backdrop claims every pointer in its
    // viewport, so a tap layer down there would never hear anything.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120 || view.hero.length < 2) return;
        _sections.cadence.jumpTo(
          (_sections.heroArt.heroIndex + (v < 0 ? 1 : -1) + view.hero.length) %
              view.hero.length,
        );
      },
      onTap: () {
        final addon = view.heroAddon;
        if (addon != null) _sections.heroArt.openHero();
      },
      child: wide,
    );
  }

  /// The pinned picture: art, trailer, scrims, and the scroll veil. Sits
  /// BEHIND the scroll view (see [_board]); everything here is
  /// non-interactive by construction.
  Widget heroBackdrop(double heroH) {
    final backdrop = _sections.heroBackdrop.heroBackdropContent(heroH);
    if (!view.animationsEnabled) return backdrop;
    // Keep the title's artwork and trailer in the hero. Fade that entire
    // layer away on scroll to reveal the fixed mountain instead of painting
    // an opaque ground veil over it. The trailer host stays mounted.
    return AnimatedBuilder(
      animation: Listenable.merge([
        _owners.scroll.scroll,
        _owners.scroll.veilMetricsRevision,
      ]),
      // TV already snaps the hero visibility on row changes. Its existing
      // bottom scrim supplies the blend without an extra offscreen mask.
      child: view.dpad
          ? backdrop
          : ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.7, 1],
              ).createShader(bounds),
              child: backdrop,
            ),
      builder: (context, child) {
        final off = _owners.scroll.scroll.hasClients
            ? _owners.scroll.scroll.offset
            : 0.0;
        final opacity = view.dpad
            ? (_owners.navigation.row < 0 ? 1.0 : 0.0)
            : (1 - off / (heroH * 0.8)).clamp(0.0, 1.0);
        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}
