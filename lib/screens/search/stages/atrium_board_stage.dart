import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/home/card_focus_rise.dart' show kCardFocusRing;
import '../stage_visuals.dart';
import '../../../widgets/skeleton_poster.dart';

// Borrowed composition slots; this widget owns no focus/notifier/native lifetime.
typedef AtriumWallContent = ({
  double Function() captionBand,
  double Function(BuildContext, double, {required double maxH}) rowBoxHeight,
  Widget Function(int offset, double height, Text label,
      {required bool isTopRow, required bool hasRowBelow}) row,
});
typedef AtriumVisualContent = ({
  Widget Function(double boardHeight) backdrop,
});

// Borrowed text inputs only; this stage creates/disposes no notifier.
typedef AtriumTextContent = ({
  ValueListenable<String?> focusedRailKey,
  ValueListenable<CanvasFavFocus?> favourite,
  ValueListenable<StremioMeta?> item,
  ValueListenable<StremioMeta?> enriched,
  ValueListenable<bool> trailerShowing,
  String Function(int offset, {String? focusedRailKey}) readTitle,
});

class AtriumStageFrame {
  const AtriumStageFrame({required this.app, required this.minimumPosterHeight, required this.hasSecondRow,
      required this.wall, required this.visuals, required this.text});
  final AppTheme app;
  final double minimumPosterHeight;
  final bool hasSecondRow;
  final AtriumWallContent wall;
  final AtriumVisualContent visuals;
  final AtriumTextContent text;
}

const double atriumLabelFontSize = 12.0;
const double _kAtriumSplit = 0.38;
const double atriumPanelPad = 48;
const double _kAtriumWallPad = 40;
const double atriumLabelGap = 10;
const double _kAtriumRowGap = 18;
const double _kAtriumWallTail = 26;
/// The share of the board Atrium's two-row wall may occupy. The row box is
/// derived from what fits inside this, so scaled labels shrink the posters
/// rather than pushing the wall off the bottom.
const double _kAtriumWallBudget = 0.64;
class AtriumStage extends StatelessWidget {
  const AtriumStage({super.key, required this.readFrame, required this.isTelevision});
  final AtriumStageFrame? Function() readFrame;
  final bool isTelevision;

  @override
  Widget build(BuildContext context) {
    final frame = readFrame();
    if (frame == null) return BrandLoadingStage(isTelevision: isTelevision);
    final app = frame.app;
    final hasSecondRow = frame.hasSecondRow;
    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        final double splitX = boardW * _kAtriumSplit;
        // ONE row height for every rail kind, filled two ways — reserving the
        // caption band on catalog rows too would cost 45px PER ROW here and
        // push the wall over three quarters of the art.
        //
        // The wall gets a BUDGET (a share of the board) and the row box is
        // derived from what fits inside it, so two scaled labels and a large
        // text scale can shrink the rows instead of running off the board.
        final labelWidth = boardW - splitX - _kAtriumWallPad * 2;
        final topLabel = _buildWallLabel(context, frame.text, 0);
        final bottomLabel = hasSecondRow ? _buildWallLabel(context, frame.text, 1) : null;
        final topLabelH = _measureLabel(context, topLabel, labelWidth);
        final bottomLabelH = bottomLabel == null
            ? 0.0
            : _measureLabel(context, bottomLabel, labelWidth);
        // The wall gets a BUDGET. If two rows at the accessibility floor
        // (scaled caption + a recognisable poster) don't fit inside it, show
        // ONE row rather than two clipped ones — the second rail is still one
        // DOWN away.
        final floorH = frame.wall.captionBand() + frame.minimumPosterHeight;
        double chromeFor(int rows) =>
            topLabelH + (rows == 2 ? bottomLabelH : 0) +
            rows * atriumLabelGap +
            (rows - 1) * _kAtriumRowGap +
            _kAtriumWallTail;
        final wallBudget = boardH * _kAtriumWallBudget;
        final twoRowsFit =
            hasSecondRow && wallBudget - chromeFor(2) >= floorH * 2;
        final showSecondRow = hasSecondRow && twoRowsFit;
        final rows = showSecondRow ? 2 : 1;
        final budget = wallBudget - chromeFor(rows);
        final rowBoxH = frame.wall.rowBoxHeight(
          context,
          min(boardH * 0.22, budget / rows),
          maxH: max(budget / rows, floorH),
        );
        final topRowUnit = topLabelH + atriumLabelGap + rowBoxH;
        final bottomRowUnit = bottomLabelH + atriumLabelGap + rowBoxH;
        final wallH =
            (showSecondRow ? topRowUnit + bottomRowUnit + _kAtriumRowGap : topRowUnit) +
            _kAtriumWallTail;

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
              child: frame.visuals.backdrop(boardH),
            ),
            // THE INK PANEL. Opaque: the board's own scaffold turns
            // transparent while a trailer plays (the shell glass stage), so
            // the column has to carry its own ground.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: splitX,
              child: ColoredBox(color: app.home.bg),
            ),
            // The seam itself — one hairline, so the cut reads as deliberate.
            Positioned(
              left: splitX,
              top: 0,
              bottom: 0,
              width: 1,
              child: ColoredBox(color: app.fade(app.core.tx, 0.09)),
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
                    horizontal: atriumPanelPad,
                    vertical: 32,
                  ),
                  child: _buildDossier(frame.text, boardH, splitX),
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
                  frame.wall.row(
                    0,
                    rowBoxH,
                    topLabel,
                    isTopRow: true,
                    hasRowBelow: showSecondRow,
                  ),
                  if (showSecondRow) ...[
                    const SizedBox(height: _kAtriumRowGap),
                    frame.wall.row(
                      1,
                      rowBoxH,
                      bottomLabel!,
                      isTopRow: false,
                      hasRowBelow: false,
                    ),
                  ],
                  const SizedBox(height: _kAtriumWallTail),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// One row of Atrium's wall: a quiet rail label over a horizontal strip of
  /// the SAME cells every other board uses.
  Text _buildWallLabel(BuildContext context, AtriumTextContent text, int offset) {
    final app = AppThemeScope.of(context);
    return Text(
      text.readTitle(offset).toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: atriumLabelFontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: app.fade(app.core.tx, 0.86),
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
      ),
    );
  }

  Widget _buildDossier(AtriumTextContent text, double boardH, double splitX) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: text.focusedRailKey,
          builder: (context, key, _) {
            final title = text.readTitle(0, focusedRailKey: key);
            return Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.6,
                color: kCardFocusRing,
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        ValueListenableBuilder<CanvasFavFocus?>(
          valueListenable: text.favourite,
          builder: (context, fav, _) => fav != null
              ? StageFavIdentity(fav: fav)
              : CanvasIdentity(
                  item: text.item,
                  enriched: text.enriched,
                  trailerShowing: text.trailerShowing,
                  // Drop the synopsis rather than clip it when
                  // the column is short (small board / large
                  // text scale).
                  variant:
                      boardH - 64 >=
                          stageNarrowIdentityH(context) + 90
                      ? StageIdentityVariant.narrow
                      : StageIdentityVariant.headline,
                  maxWidth: (splitX - atriumPanelPad * 2).clamp(
                    120.0,
                    520.0,
                  ),
                ),
        ),
      ],
    );

  // Atrium plain labels only: measure the same inherited Text configuration,
  // without changing the legacy metric used by Deck and Tonight.
  double _measureLabel(BuildContext context, Text label, double width) {
    final defaults = DefaultTextStyle.of(context);
    var style = defaults.style.merge(label.style);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final lineHeight = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
    final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
    if (lineHeight != null || letterSpacing != null || wordSpacing != null) {
      style = style.merge(TextStyle(
        height: lineHeight,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
      ));
    }
    final overflow = label.overflow ?? style.overflow ?? defaults.overflow;
    final painter = TextPainter(
      text: TextSpan(text: label.data, style: style, locale: label.locale),
      textAlign: label.textAlign ?? defaults.textAlign ?? TextAlign.start,
      textDirection: label.textDirection ?? Directionality.of(context),
      textScaler: label.textScaler ?? MediaQuery.textScalerOf(context),
      maxLines: label.maxLines ?? defaults.maxLines,
      ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
      locale: label.locale ?? Localizations.maybeLocaleOf(context),
      strutStyle: label.strutStyle?.merge(StrutStyle(height: lineHeight)),
      textWidthBasis: label.textWidthBasis ?? defaults.textWidthBasis,
      textHeightBehavior: label.textHeightBehavior ??
          defaults.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
    );
    try {
      painter.layout(
        minWidth: 0,
        maxWidth: (label.softWrap ?? defaults.softWrap) || overflow == TextOverflow.ellipsis
            ? width
            : double.infinity,
      );
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

}
