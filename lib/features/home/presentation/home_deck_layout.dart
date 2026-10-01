import 'dart:math' show max;

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

import 'home_stage_corner_painter.dart';

// DECK metrics.
const double _kDeckPanelPad = 48;
const double _kDeckCardRightPad = 36;
const double homeDeckCardRadius = 22;
const double _kDeckRailGap = 18;
const double _kDeckRailTail = 26;

/// Deck's card uses only the space left after reserving its rail.
class HomeDeckGeometry {
  const HomeDeckGeometry._({
    required this.railBoxH,
    required this.railZoneH,
    required this.labelGap,
    required this.cardLeft,
    required this.cardTop,
    required this.cardW,
    required this.cardH,
  });
  final double railBoxH;
  final double railZoneH;
  final double labelGap;
  final double cardLeft;
  final double cardTop;
  final double cardW;
  final double cardH;
  double get identityWidth =>
      (cardLeft - _kDeckPanelPad - 40).clamp(140.0, 560.0);

  factory HomeDeckGeometry({
    required double boardW,
    required double boardH,
    required double railBoxH,
    required double labelHeight,
    required double labelGap,
  }) {
    final railZoneH = labelHeight + labelGap + railBoxH + _kDeckRailTail;
    final cardTop = boardH * 0.11;
    // The TRUE remainder — never clamped up, which would hand the card
    // height the rail has already been promised.
    var cardH = max(0.0, boardH - cardTop - railZoneH - _kDeckRailGap);
    var cardW = cardH * 16 / 9;
    final maxCardW = boardW * 0.56;
    if (cardW > maxCardW) {
      cardW = maxCardW;
      cardH = cardW * 9 / 16;
    }
    final cardLeft = boardW - cardW - _kDeckCardRightPad;

    return HomeDeckGeometry._(
      railBoxH: railBoxH,
      railZoneH: railZoneH,
      labelGap: labelGap,
      cardLeft: cardLeft,
      cardTop: cardTop,
      cardW: cardW,
      cardH: cardH,
    );
  }
}

/// Deck's video-card frame, dossier and theater rail. Supplied content keeps
/// its caller-owned metadata, focus, navigation and native resource lifetimes.
Widget buildHomeDeckLayout({
  required HomeDeckGeometry geometry,
  required bool theater,
  required String railKey,
  required int itemCount,
  required Color borderColor,
  required Widget peeks,
  required Widget artwork,
  required Widget? trailer,
  required Widget? live,
  required Widget identity,
  required Widget railLabel,
  required IndexedWidgetBuilder itemBuilder,
}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      // Constant ground — a single radial, never tweened.
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.55, -0.35),
              radius: 1.15,
              colors: [Color(0xFF1B1730), Color(0xFF0C0A16), Color(0xFF08070F)],
              stops: [0.0, 0.62, 1.0],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
      // The deck's two peek cards — STATIC art of the next two titles
      // on this rail. Never a second video: one engine, one card.
      // Listens to the focused column so the stack DEALS as you move;
      // only this subtree rebuilds.
      peeks,
      // THE CARD.
      Positioned(
        left: geometry.cardLeft,
        top: geometry.cardTop,
        width: geometry.cardW,
        height: geometry.cardH,
        child: Stack(
          fit: StackFit.expand,
          children: [
            artwork,
            if (trailer != null) trailer,
            if (live != null) live,
            // Rounded corners WITHOUT a clip: four ink wedges painted
            // over the layers. A ClipRRect here would wrap the punch
            // hole in a saveLayer and break the blend.
            const IgnorePointer(
              child: CustomPaint(
                painter: HomeStageCornerPainter(
                  radius: homeDeckCardRadius,
                  color: Color(0xFF0C0A16),
                ),
                child: SizedBox.expand(),
              ),
            ),
            // A hairline inside the wedges reads as the card's edge.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(homeDeckCardRadius),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
      // IDENTITY column, left of the card.
      Positioned(
        left: _kDeckPanelPad,
        top: 0,
        width: geometry.identityWidth,
        bottom: geometry.railZoneH,
        child: IgnorePointer(
          child: Align(alignment: Alignment.centerLeft, child: identity),
        ),
      ),
      // The rail. Recedes with the lights in theater, cells still
      // MOUNTED so focus survives.
      Positioned(
        left: _kDeckPanelPad,
        right: 0,
        bottom: 0,
        child: AnimatedSlide(
          offset: theater ? const Offset(0, 0.12) : Offset.zero,
          duration: theater
              ? const Duration(milliseconds: 900)
              : const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: theater ? 0.0 : 1.0,
            duration: theater
                ? const Duration(milliseconds: 900)
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: _kDeckPanelPad),
                  child: railLabel,
                ),
                SizedBox(height: geometry.labelGap),
                SizedBox(
                  height: geometry.railBoxH,
                  child: ListView.builder(
                    key: ValueKey('deck-rail-$railKey'),
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.hardEdge,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(400),
                    itemCount: itemCount,
                    itemBuilder: itemBuilder,
                  ),
                ),
                const SizedBox(height: _kDeckRailTail),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
