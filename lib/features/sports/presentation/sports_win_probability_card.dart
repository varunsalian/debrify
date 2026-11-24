// Who is likely to win: the in-game win-probability chart once play starts,
// or the pre-game matchup predictor before it.
//
// Presentation layer. The chart is decorative detail for the headline above
// it, so a screen reader hears the headline ("Lions 72% to win") rather than
// a description of the line.
import 'dart:math' as math;

import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_stats_frame.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _chartHeight = 120.0;

/// The headline: the side ahead and its chance, rounded to a whole percent.
({SportsMatchSide side, int percent})? sportsWinLeader(SportsMatchStats stats) {
  final points = stats.winProbability;
  if (points.length >= 2) {
    final home = points.last;
    return home >= 0.5
        ? (side: stats.home, percent: (home * 100).round())
        : (side: stats.away, percent: ((1 - home) * 100).round());
  }
  final prediction = stats.prediction;
  if (prediction == null) return null;
  final total = prediction.home + prediction.away;
  final home = prediction.home / total;
  return home >= 0.5
      ? (side: stats.home, percent: (home * 100).round())
      : (side: stats.away, percent: ((1 - home) * 100).round());
}

class SportsWinProbabilityCard extends StatelessWidget {
  const SportsWinProbabilityCard({
    super.key,
    required this.stats,
    required this.colors,
    this.autofocus = false,
  });

  final SportsMatchStats stats;
  final ({Color home, Color away}) colors;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final chart = stats.winProbability.length >= 2;
    final leader = sportsWinLeader(stats)!;
    final tag = switch (stats.status) {
      SportsEventStatus.finished => 'Final',
      SportsEventStatus.live => 'Live',
      _ => null,
    };
    final headline = '${leader.side.abbreviation} ${leader.percent}%';
    final title = chart ? 'Win probability' : 'Matchup predictor';
    return SportsStatsCard(
      title: title,
      children: [
        SportsStatsFocusRow(
          autofocus: autofocus,
          label: [
            title,
            '${leader.side.name} ${leader.percent}% to win',
            ?tag,
          ].join(', '),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wraps rather than overflows at large text sizes on phones.
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  sportsLabelText(
                    headline,
                    _tokens.fg,
                    size: 22,
                    weight: FontWeight.w700,
                    tabular: true,
                  ),
                  if (tag != null)
                    sportsLabelText(
                      tag,
                      stats.status == SportsEventStatus.live
                          ? _tokens.live
                          : _tokens.fgDim,
                      size: 12,
                      weight: FontWeight.w700,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (chart) _chart() else _predictorBar(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chart() => SizedBox(
    height: _chartHeight,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 40,
          height: _chartHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              sportsLabelText(
                stats.home.abbreviation,
                colors.home,
                size: 11,
                weight: FontWeight.w700,
                ellipsize: true,
              ),
              sportsLabelText(
                stats.away.abbreviation,
                colors.away,
                size: 11,
                weight: FontWeight.w700,
                ellipsize: true,
              ),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            height: _chartHeight,
            child: CustomPaint(
              painter: SportsWinProbabilityPainter(
                points: stats.winProbability,
                home: colors.home,
                away: colors.away,
                grid: _tokens.hairline2,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _predictorBar() {
    final prediction = stats.prediction!;
    final total = prediction.home + prediction.away;
    final homeShare = (prediction.home / total).clamp(0.0, 1.0);
    String percent(double value) => '${(value / total * 100).round()}%';
    Widget side(SportsMatchSide team, String value, Color color, bool end) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (end) ...[
              sportsLabelText(value, _tokens.fg, weight: FontWeight.w700),
              const SizedBox(width: 6),
            ],
            sportsLabelText(team.abbreviation, color, weight: FontWeight.w700),
            if (!end) ...[
              const SizedBox(width: 6),
              sportsLabelText(value, _tokens.fg, weight: FontWeight.w700),
            ],
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: math.max(1, (homeShare * 1000).round()),
                  child: ColoredBox(color: colors.home),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: math.max(1, ((1 - homeShare) * 1000).round()),
                  child: ColoredBox(color: colors.away),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: side(
                  stats.home,
                  percent(prediction.home),
                  colors.home,
                  false,
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: side(
                  stats.away,
                  percent(prediction.away),
                  colors.away,
                  true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The home side's chance over the game: the line runs left to right, high
/// means home ahead; the area between the line and 50 % takes the colour of
/// whoever leads at that moment.
class SportsWinProbabilityPainter extends CustomPainter {
  const SportsWinProbabilityPainter({
    required this.points,
    required this.home,
    required this.away,
    required this.grid,
  });

  final List<double> points;
  final Color home;
  final Color away;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final mid = size.height / 2;
    final step = size.width / (points.length - 1);
    Offset at(int i) => Offset(i * step, (1 - points[i]) * size.height);

    final line = Path()..moveTo(0, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, mid)
      ..lineTo(0, mid)
      ..close();

    final upper = Rect.fromLTRB(0, 0, size.width, mid);
    final lower = Rect.fromLTRB(0, mid, size.width, size.height);
    for (final (rect, color) in [(upper, home), (lower, away)]) {
      canvas
        ..save()
        ..clipRect(rect)
        ..drawPath(area, Paint()..color = color.withValues(alpha: 0.28))
        ..drawPath(
          line,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeJoin = StrokeJoin.round,
        )
        ..restore();
    }
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(SportsWinProbabilityPainter old) =>
      !identical(old.points, points) ||
      old.home != home ||
      old.away != away ||
      old.grid != grid;
}
