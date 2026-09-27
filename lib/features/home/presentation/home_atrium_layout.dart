import 'package:flutter/widgets.dart';
import 'home_stage_scrims.dart';

// Shared with the caller's row budget and identity width calculations.
const double homeAtriumPanelPadding = 48;
const double homeAtriumRowGap = 18;
const double homeAtriumWallTail = 26;
const double _kAtriumWallPad = 40;

/// Atrium's opaque dossier beside artwork and the bottom rail wall.
/// The caller retains rail geometry/selection, focus and native surface ownership.
/// Optional surfaces and the second row are constructed only when needed.
Widget buildHomeAtriumLayout({
  required double splitX,
  required double wallH,
  required Color panelColor,
  required Color seamColor,
  required Widget artwork,
  required Widget? trailer,
  required Widget? live,
  required Widget railLabel,
  required Widget identity,
  required Widget topRow,
  required Widget? bottomRow,
}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      // ART COLUMN — the right side only. The trailer layer is laid out
      // in the same rect, so the punch hole is exactly this box and the
      // video replaces the art in place with no geometry jump.
      Positioned(
        left: splitX,
        top: 0,
        right: 0,
        bottom: 0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            artwork,
            if (trailer != null) trailer,
            if (live != null) live,
            const IgnorePointer(
              child: HomeStageScrims(variant: HomeStageScrimVariant.seam),
            ),
          ],
        ),
      ),
      // THE INK PANEL. Opaque: the board's own scaffold turns
      // transparent while a trailer plays (the shell glass stage), so
      // the column has to carry its own ground.
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: splitX,
        child: ColoredBox(color: panelColor),
      ),
      // The seam itself — one hairline, so the cut reads as deliberate.
      Positioned(
        left: splitX,
        top: 0,
        bottom: 0,
        width: 1,
        child: ColoredBox(color: seamColor),
      ),
      // THE DOSSIER. Never focusable; vertically centred in the column.
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: splitX,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: homeAtriumPanelPadding,
              vertical: 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [railLabel, const SizedBox(height: 22), identity],
            ),
          ),
        ),
      ),
      // THE WALL — two rails, stacked, over the art's lower half.
      Positioned(
        left: splitX + _kAtriumWallPad,
        right: _kAtriumWallPad,
        bottom: 0,
        height: wallH,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            topRow,
            if (bottomRow != null) ...[
              const SizedBox(height: homeAtriumRowGap),
              bottomRow,
            ],
            const SizedBox(height: homeAtriumWallTail),
          ],
        ),
      ),
    ],
  );
}
