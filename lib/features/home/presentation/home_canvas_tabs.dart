import 'dart:math' show max;
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

// Metrics for the Canvas bottom column (rail tabs + shelf). Same contract as
// HomeArtCaption: the widgets and the identity block that has to stay
// CLEAR of them read the same numbers, so neither can drift into the other.
// (It drifted once: growing the shelf box by the caption band silently ate the
// identity's whole clearance and the tabs landed on the synopsis.)
const double _kCanvasTabFontSize = 12.5;
const double _kCanvasTabUnderlineGap = 6;
const double _kCanvasTabUnderline = 2.5;

/// Floor for the tab row: the stacked chevron pair beside the labels — two
/// 13px icons (the second is only translated, so it still occupies its line)
/// plus 1px of bottom padding.
const double homeCanvasChevronColumnHeight = 27;

/// Height of the Canvas rail-tab row at the current text scale.
double homeCanvasTabsHeight(BuildContext context) => max(
  homeCanvasChevronColumnHeight,
  MediaQuery.textScalerOf(context).scale(_kCanvasTabFontSize) * 1.35 +
      _kCanvasTabUnderlineGap +
      _kCanvasTabUnderline,
);

/// Quiet rail-name tabs above the Canvas shelf — a window around the
/// active rail (display only; UP/DOWN does the switching). The window is
/// sized to what actually FITS: at some Screen Size settings the board is
/// narrow enough that four capped labels + chevrons + the "+N more" tail
/// would overflow the Row.
Widget buildHomeCanvasTabs({
  required BuildContext context,
  required int railCount,
  required int active,
  required String Function(int index) titleAt,
}) {
  final app = AppThemeScope.of(context);
  return LayoutBuilder(
    builder: (context, cons) {
      // Worst-case per-tab footprint: 170px label cap + 26px gap. Reserve
      // the chevron affordance (~25px) and the "+N more" tail (~92px).
      const perTab = 196.0;
      const reserved = 25.0 + 92.0;
      // May legitimately be ZERO: a narrow board (Mosaic's header shares its
      // width with the identity, and Screen Size can shrink the board) has
      // room for the chevrons and the "+N more" tail but not a label — and
      // an unflexible label there would overflow the Row.
      final maxTabs = (((cons.maxWidth - reserved) / perTab).floor()).clamp(
        0,
        4,
      );
      // Zero tabs fit: show no labels at all, but still say how many rails
      // there are (otherwise the row is a pair of chevrons with no context).
      // Leading CONTEXT (starting one rail early) only makes sense once there
      // is room for more than one label. With a single slot, starting at
      // `active - 1` put the ONLY visible label on the rail BEFORE the active
      // one — so the strip named a rail the board wasn't showing, and nothing
      // was styled active because `i == active` never matched. The window must
      // always contain the active rail.
      var start = switch (maxTabs) {
        0 => 0,
        1 => active,
        _ => active - 1,
      };
      if (maxTabs > 0 && start > railCount - maxTabs) {
        start = railCount - maxTabs;
      }
      if (start < 0) start = 0;
      var end = start + maxTabs;
      if (end > railCount) end = railCount;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // UP/DOWN affordance: a quiet stacked chevron pair in front of the
          // rail names — the one visual clue that vertical DPAD is what
          // switches them (they sit above the shelf, so nothing else says so).
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 13,
                  color: app.fade(app.core.tx, 0.45),
                ),
                Transform.translate(
                  offset: const Offset(0, -5),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 13,
                    color: app.fade(app.core.tx, 0.45),
                  ),
                ),
              ],
            ),
          ),
          for (var i = start; i < end; i++)
            if (titleAt(i).isNotEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          titleAt(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: _kCanvasTabFontSize,
                            fontWeight: i == active
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.3,
                            color: i == active
                                ? app.core.tx
                                : app.fade(app.core.tx, 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kCanvasTabUnderlineGap),
                      Container(
                        height: _kCanvasTabUnderline,
                        width: 26,
                        decoration: BoxDecoration(
                          borderRadius: app.shape.br(2),
                          color: i == active ? app.core.tx : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (end < railCount)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                '+${railCount - end} more',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: app.fade(app.core.tx, 0.24),
                ),
              ),
            ),
        ],
      );
    },
  );
}
