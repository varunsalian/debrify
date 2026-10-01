import 'dart:math' show max, min;
import 'package:flutter/widgets.dart';
import 'home_stage_corner_painter.dart';

// TONIGHT metrics. The rail zone is reserved first and the main zone takes
// what is left, so a short board shrinks the card and drops queue rows rather
// than overlapping them.

const double homeTonightHorizontalPadding = 48;
const double _kTonightZoneGap = 22;
const double homeTonightRailTail = 24;
const double homeTonightRowGap = 12;
const double _kTonightRowMaxH = 118;
const double _kTonightQueueMinW = 260;
const double _kTonightCardRadius = 14;

/// Tonight's queue/card geometry after reserving its header and rail.
class HomeTonightGeometry {
  const HomeTonightGeometry._({
    required this.headerH,
    required this.cardW,
    required this.cardH,
    required this.queueOnly,
    required this.showQueue,
    required this.effQueueW,
    required this.rowH,
    required this.queueBoxH,
  });
  final double headerH;
  final double cardW;
  final double cardH;
  final bool queueOnly;
  final bool showQueue;
  final double effQueueW;
  final double rowH;
  final double queueBoxH;

  factory HomeTonightGeometry({
    required double boardW,
    required double boardH,
    required bool hasRail,
    required bool hasQueue,
    required double railBoxH,
    required double labelHeight,
    required double labelGap,
    required double headerH,
    required double rowMinH,
  }) {
    final double railZoneH = !hasRail
        ? 0
        : labelHeight + labelGap + railBoxH + homeTonightRailTail;
    // The TRUE remainder: clamping this up would re-spend the header's and
    // the rail's reserved height and push them off the board.
    final mainH = max(0.0, boardH - headerH - railZoneH - _kTonightZoneGap);

    var cardH = mainH;
    var cardW = cardH * 16 / 9;
    final maxCardW = boardW * 0.58;
    if (cardW > maxCardW) {
      cardW = maxCardW;
      cardH = cardW * 9 / 16;
    }
    // The queue is the whole point of Tonight, so a board too narrow to
    // hold both shrinks the CARD, never the queue. Only a board narrower
    // than roughly a card floor plus the queue's minimum drops it — and
    // then only when there is a rail left to hold focus.
    if (hasQueue) {
      final maxWithQueue =
          boardW -
          homeTonightHorizontalPadding * 2 -
          _kTonightZoneGap -
          _kTonightQueueMinW;
      if (cardW > maxWithQueue) {
        // Shrink toward the queue, but NEVER widen past what the vertical
        // remainder allows — a wider card is a taller card, and that
        // height belongs to the rail.
        cardW = min(max(maxWithQueue, boardW * 0.34), mainH * 16 / 9);
        cardH = cardW * 9 / 16;
      }
    }
    // How many rows actually FIT — never a fixed four.
    // What a row actually needs at this text scale: two lines of type,
    // the progress bar, their gaps and the row's own padding. Below one
    // of these the queue simply isn't drawn — a 1px row would overflow.
    // Zero rows is allowed — but never when the queue is the ONLY thing
    // that could hold focus, or the board would have nothing focusable.
    final minRows = (!hasRail && hasQueue) ? 1 : 0;
    final visibleRows = (mainH / (rowMinH + homeTonightRowGap)).floor().clamp(
      minRows,
      4,
    );
    final queueW =
        (boardW - cardW - homeTonightHorizontalPadding * 2 - _kTonightZoneGap)
            .clamp(0.0, boardW);
    // Never leave the board with nothing focusable: if the queue can't be
    // drawn and there is no rail either, draw it anyway.
    // With no rail beneath it the queue is the ONLY focusable zone, so
    // it takes the whole board and the card steps aside entirely rather
    // than squeezing it to nothing.
    final queueOnly = !hasRail && hasQueue;
    final effQueueW = queueOnly
        ? max(1.0, boardW - homeTonightHorizontalPadding * 2)
        : queueW;
    final showQueue =
        hasQueue &&
        visibleRows > 0 &&
        (queueOnly || effQueueW >= _kTonightQueueMinW) &&
        effQueueW > 0;
    // Never taller than the share it actually has: the row height is the
    // MIN of what looks right and what fits.
    final rowH = visibleRows == 0
        ? 0.0
        : min(
            max(
              (mainH - (visibleRows - 1) * homeTonightRowGap) / visibleRows,
              rowMinH,
            ),
            _kTonightRowMaxH,
          );
    final queueBoxH = visibleRows == 0
        ? 0.0
        : (rowH * visibleRows + homeTonightRowGap * (visibleRows - 1)).clamp(
            0.0,
            mainH,
          );

    return HomeTonightGeometry._(
      headerH: headerH,
      cardW: cardW,
      cardH: cardH,
      queueOnly: queueOnly,
      showQueue: showQueue,
      effQueueW: effQueueW,
      rowH: rowH,
      queueBoxH: queueBoxH,
    );
  }
}

/// Tonight's three zones. Optional content is constructed lazily in its original
/// order; the caller retains focus-zone decisions, actions and resource owners.
Widget buildHomeTonightLayout({
  required HomeTonightGeometry geometry,
  required Widget header,
  required Widget Function() cardBuilder,
  required Widget Function() queueBuilder,
  required Widget Function()? railBuilder,
}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      // Constant ground — one gradient, never tweened.
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF161227), Color(0xFF0E0C1B), Color(0xFF0A0813)],
              stops: [0.0, 0.46, 1.0],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
      Positioned(
        left: homeTonightHorizontalPadding,
        right: homeTonightHorizontalPadding,
        top: 0,
        height: geometry.headerH,
        child: header,
      ),
      // THE CARD — art, trailer and live all in this rect, so the punch
      // hole is exactly the card. Stood down in queue-only mode, where
      // the queue owns the board.
      if (!(geometry.queueOnly && geometry.showQueue))
        Positioned(
          left: homeTonightHorizontalPadding,
          top: geometry.headerH,
          width: geometry.cardW,
          height: geometry.cardH,
          child: cardBuilder(),
        ),
      // THE QUEUE.
      if (geometry.showQueue)
        Positioned(
          left: geometry.queueOnly
              ? homeTonightHorizontalPadding
              : homeTonightHorizontalPadding +
                    geometry.cardW +
                    _kTonightZoneGap,
          top: geometry.headerH,
          width: geometry.effQueueW,
          height: max(geometry.rowH, geometry.queueBoxH),
          child: queueBuilder(),
        ),
      // THE RAIL.
      if (railBuilder != null)
        Positioned(
          left: homeTonightHorizontalPadding,
          right: 0,
          bottom: 0,
          child: railBuilder(),
        ),
    ],
  );
}

/// Artwork, native surface slots and caption in Tonight's original card frame.
Widget buildHomeTonightCardFrame({
  required Widget artwork,
  required Widget? trailer,
  required Widget? live,
  required Widget caption,
}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      artwork,
      if (trailer != null) trailer,
      if (live != null) live,
      // Legibility ramp + the caption block, painted ABOVE the
      // hole (plain draws only).
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xF00A0810), Color(0xA00A0810), Color(0x000A0810)],
              stops: [0.0, 0.30, 0.68],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
      const IgnorePointer(
        child: CustomPaint(
          painter: HomeStageCornerPainter(
            radius: _kTonightCardRadius,
            color: Color(0xFF100D1F),
          ),
          child: SizedBox.expand(),
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        bottom: 20,
        child: IgnorePointer(child: caption),
      ),
    ],
  );
}
