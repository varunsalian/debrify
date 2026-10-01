import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/home_tonight_card_info.dart';
import 'home_board_media.dart';
import 'home_tonight_card_caption.dart';
import 'home_tonight_header.dart';
import 'home_tonight_layout.dart';

/// Tonight's media card, continuation queue and lower rail. Geometry keeps the
/// rail visible on short boards; the host retains queue/rail focus ownership.
Widget buildHomeTonightBoard({
  required BuildContext hostContext,
  required int queueCount,
  required bool hasRail,
  required HomeBoardMedia Function() media,
  required bool Function() trailerActive,
  required ValueListenable<HomeTonightCardInfo?> cardInfo,
  required double Function(BuildContext) labelHeight,
  required double labelGap,
  required double Function(BuildContext, double, {required double maxH})
  railBoxHeight,
  required VoidCallback onQueueHidden,
  required Widget Function(double rowHeight, double queueWidth) queueBuilder,
  required Widget Function(double height, bool queueAbove)? railBuilder,
}) {
  return LayoutBuilder(
    builder: (context, cons) {
      final surfaces = media();
      final boardW = cons.maxWidth;
      final boardH = cons.maxHeight;

      // ── Geometry, derived bottom-up. The rail zone is reserved FIRST,
      // then the main zone takes what is left, then the card and the queue
      // rows are sized from that — so nothing can overlap on a short board.
      final labelH = labelHeight(context);
      final double railBoxH = !hasRail
          ? 0
          : railBoxHeight(context, boardH * 0.21, maxH: boardH * 0.30);
      final geometry = HomeTonightGeometry(
        boardW: boardW,
        boardH: boardH,
        hasRail: hasRail,
        hasQueue: queueCount > 0,
        railBoxH: railBoxH,
        labelHeight: labelH,
        labelGap: labelGap,
        headerH: homeTonightHeaderHeight(context),
        rowMinH: _tonightRowMinHeight(context),
      );
      // A zone that isn't on screen must not be the one holding focus.
      if (!geometry.showQueue && hasRail) {
        onQueueHidden();
      }
      return buildHomeTonightLayout(
        geometry: geometry,
        header: buildHomeTonightHeader(
          context: hostContext,
          inProgress: queueCount,
          now: DateTime.now(),
        ),
        cardBuilder: () => buildHomeTonightCardFrame(
          artwork: surfaces.artwork(),
          trailer: trailerActive()
              ? surfaces.trailerLayer(geometry.cardH, fullBleed: true)
              : null,
          live: trailerActive()
              ? surfaces.liveLayer(geometry.cardH, fullBleed: true)
              : null,
          caption: HomeTonightCardCaption(
            item: surfaces.item,
            enriched: surfaces.enriched,
            fav: surfaces.favorite,
            info: cardInfo,
          ),
        ),
        queueBuilder: () => queueBuilder(geometry.rowH, geometry.effQueueW),
        railBuilder: railBuilder == null
            ? null
            : () => railBuilder(railBoxH, queueCount > 0 && geometry.showQueue),
      );
    },
  );
}

/// A queue row's true minimum at the current text scale: title + episode +
/// their gaps + the progress bar + the row's vertical padding.
double _tonightRowMinHeight(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  return t.scale(13.5) * 1.25 + 5 + t.scale(11.5) * 1.25 + 9 + 4 + 20 + 4;
}
