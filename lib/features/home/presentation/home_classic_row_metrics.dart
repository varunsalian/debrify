import 'dart:math';
import 'package:flutter/widgets.dart';
import '../../../widgets/home/row_tag_pill.dart';

/// Poster width of a Home board rail card — the single source for every
/// surface that must look like a Home row (the board itself, collection
/// folder rails).
double homeRailPosterWidth(
  BuildContext context, {
  required bool isTelevision,
  bool searchResults = false,
}) {
  if (!isTelevision) {
    return MediaQuery.sizeOf(context).width >= 900 ? 162.0 : 118.0;
  }
  final height = MediaQuery.sizeOf(context).height;
  return searchResults
      ? (height * 0.225).clamp(120.0, 180.0)
      : (height * 0.17).clamp(92.0, 140.0);
}

/// Shared card orientation for classic rails and the stage/board callers.
double homeTitleCardAspect({required bool landscape}) =>
    landscape ? 16 / 9 : 2 / 3;

/// Landscape cards keep the original 1.6x poster width and 16:9 artwork.
Size homeClassicCardSize({
  required double posterWidth,
  required bool landscape,
}) {
  final width = landscape ? posterWidth * 1.6 : posterWidth;
  return Size(width, width / homeTitleCardAspect(landscape: landscape));
}

/// Leave one title-card row and a 24px next-header peek below the TV hero.
/// Search retains its fixed compact 150px strip. Favourites do not affect it.
double homeClassicHeroBudget({
  required double boardHeight,
  required double cardHeight,
  required bool isTelevision,
  required bool searchResults,
}) {
  final headerHeight = isTelevision ? 44.0 : 52.0;
  final rowHeight = cardHeight + 14;
  return (boardHeight - headerHeight - rowHeight - 24).clamp(
    150.0,
    searchResults ? 150.0 : 440.0,
  );
}

/// Fallback height for preserving a classic scroll anchor during row insertion.
/// The caller supplies its original title-style context separately from this
/// layout context. Hidden collection headers never resolve fonts or measure text.
double measureHomeClassicRowExtent(
  BuildContext context, {
  required bool hideHeader,
  required bool hideSourceTags,
  required TextStyle Function() titleStyle,
  required double Function() cardHeight,
}) {
  double lineHeight(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Ag',
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  if (hideHeader) return 8 + cardHeight() + 14;
  var header = lineHeight(titleStyle());
  if (!hideSourceTags) {
    header = max(header, lineHeight(RowTagPill.textStyle(9.5)) + 9.5 * .56 + 2);
  }
  return 14 + header + 10 + cardHeight() + 14;
}
