import 'package:flutter/widgets.dart';

/// Continue Watching progress-bar fill and favourite-card live indicator.
const Color homeCardProgressRed = Color(0xFFE50914);

/// Shared by the favourite caption and the layouts reserving space for it.
abstract final class HomeArtCaption {
  static const double gap = 10;
  static const double fontSize = 14;
  static const double lineHeight = 1.25;
  static const int maxLines = 2;

  /// Paragraph layout rounds each line separately: two 17.5px lines render
  /// at 18px each, so reserve whole pixels per line at the current text scale.
  static double band(BuildContext context) =>
      gap +
      (MediaQuery.textScalerOf(context).scale(fontSize) * lineHeight)
              .ceilToDouble() *
          maxLines;
}
