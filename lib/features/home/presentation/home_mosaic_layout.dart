import 'dart:math' show max;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../models/iptv_playlist.dart';
import 'home_stage_identity.dart';

// MOSAIC metrics. The head band is a FIXED height so the wall below it never
// shifts when a title's logo is taller than the last one's.
const double _kMosaicPadX = 48;
const double _kMosaicGap = 16;
const double _kMosaicHeadTop = 26;

/// The identity band's height is DERIVED from the scaled content it holds —
/// a fixed band clipped the logo and its meta line at large text scales.
double _mosaicHeadHeight(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  // A title with no logo art falls back to TEXT, which scales — the band has
  // to reserve whichever of the two is taller.
  final titleH = max(
    homeStageHeadlineLogoHeight,
    t.scale(homeStageHeadlineTitleSize) * 1.25,
  );
  // Facts line, then the genres on their own line beneath it. The right-hand
  // column (rail label + hold hint) is shorter than that, so the identity
  // still sets the band's height.
  return titleH + 10 + t.scale(12.5) * 1.4 + 6 + t.scale(12.5) * 1.4 + 6;
}

const double _kMosaicHeadGap = 18;

/// One calculation shared by Mosaic's grid and its caller-owned navigation.
class HomeMosaicGeometry {
  const HomeMosaicGeometry._(this.gridW, this.perRow, this.cellW, this.extent);
  final double gridW;
  final int perRow;
  final double cellW;
  final double extent;

  factory HomeMosaicGeometry({
    required double boardW,
    required double boardH,
    required double cellAspect,
    required double captionBandHeight,
  }) {
    // Never negative: a board narrower than its own padding would make
    // every derived width negative and trip a layout assertion.
    final gridW = max(1.0, boardW - _kMosaicPadX * 2);
    // A grid only ever shows ONE rail, and a rail is homogeneous — so
    // the whole wall takes one shape: favourites are always portrait,
    // title cells follow the Home Cards orientation.
    // Aim for a cell about a third of the board's height — landscape a
    // little shorter, or three backdrops swallow the whole wall — then
    // take whatever whole number of columns actually FITS, as few as one.
    final targetH = boardH * (cellAspect > 1 ? 0.24 : 0.30);
    final targetW = max(1.0, targetH * cellAspect);
    final perRow = (gridW / (targetW + _kMosaicGap)).floor().clamp(1, 8);
    final cellW = max(1.0, (gridW - (perRow - 1) * _kMosaicGap) / perRow);
    // The extent is exactly what this rail's kind needs: the art box,
    // plus the caption band only when the cells actually carry one.
    final extent = cellW / cellAspect + captionBandHeight;

    return HomeMosaicGeometry._(gridW, perRow, cellW, extent);
  }
}

/// Mosaic's fixed header, live-dependent veils and keyed lazy grid.
/// Signals are borrowed; the caller owns selection, actions and native playback.
Widget buildHomeMosaicLayout({
  required BuildContext context,
  required HomeMosaicGeometry geometry,
  required String railKey,
  required int itemCount,
  required Widget artwork,
  required Widget? liveSurface,
  required ValueListenable<IptvChannel?> liveChannel,
  required Widget identity,
  required Widget railLabel,
  required bool showRailHint,
  required Color hintColor,
  required IndexedWidgetBuilder itemBuilder,
}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      artwork,
      // Constant veil. It SNAPS (no tween): a full-screen gradient
      // tween is the single most expensive thing this board could do.
      // While a favourite CHANNEL is previewing, the veil lifts so the
      // live picture is actually visible behind the wall.
      ValueListenableBuilder<IptvChannel?>(
        valueListenable: liveChannel,
        builder: (context, live, _) => IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: live == null
                  ? const Color(0xDE0D0B1A)
                  : const Color(0x9E0D0B1A),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      // The live feed sits ABOVE the veil (a veiled video is a waste of
      // a decoder) with its own lighter scrim for the grid's sake.
      if (liveSurface != null) liveSurface,
      ValueListenableBuilder<IptvChannel?>(
        valueListenable: liveChannel,
        builder: (context, live, _) => IgnorePointer(
          child: live == null
              ? const SizedBox.shrink()
              : const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x8C0D0B1A)),
                  child: SizedBox.expand(),
                ),
        ),
      ),
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.85, -0.95),
              radius: 1.25,
              colors: [Color(0x2E7B5CFF), Color(0x000D0B1A)],
              stops: [0.0, 0.62],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kMosaicPadX),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: _kMosaicHeadTop),
            // Identity band: the wall's only chrome. Fixed height so
            // the grid below it never shifts as titles change.
            SizedBox(
              height: _mosaicHeadHeight(context),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 32),
                  // The windowed TAB STRIP needs the full board width
                  // to show useful context; here it shares a row with
                  // the identity and collapses to a single slot, which
                  // is both cramped and (before the window fix) the
                  // wrong rail. The compact label says the same thing
                  // in a fraction of the width and is correct by
                  // construction: it names the ACTIVE rail and its
                  // position among all of them.
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          railLabel,
                          if (showRailHint) ...[
                            const SizedBox(height: 8),
                            // The grid can page for as long as the
                            // catalog has more, so "walk to the last
                            // line" is not a way out of it. The hold
                            // gesture is the way out, and a gesture
                            // nothing announces may as well not exist.
                            Text(
                              'HOLD ▲▼ TO CHANGE ROW',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                                color: hintColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _kMosaicHeadGap),
            Expanded(
              child: GridView.builder(
                // Keyed by rail IDENTITY: a rail streaming in above the
                // active one must never swap the wall's contents.
                key: ValueKey('mosaic-rail-$railKey'),
                padding: const EdgeInsets.only(bottom: 24),
                clipBehavior: Clip.hardEdge,
                scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: geometry.perRow,
                  crossAxisSpacing: _kMosaicGap,
                  mainAxisSpacing: _kMosaicGap,
                  mainAxisExtent: geometry.extent,
                ),
                itemCount: itemCount,
                itemBuilder: (context, col) => Center(
                  child: SizedBox(
                    width: geometry.cellW,
                    child: itemBuilder(context, col),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
