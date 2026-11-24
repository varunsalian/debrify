// Team stats side by side: home on the left, away on the right, the label
// between them and a pair of bars growing out from the middle.
//
// Presentation layer: draws the rows [sportsStatRows] chose. Each side's bar
// is its value over the larger of the two, so the bigger figure's bar is
// full; the side the stat favours (the smaller one for turnovers, fouls and
// the like) gets bold figures and the brighter bar.
import 'package:debrify/features/sports/application/sports_match_stat_rows.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_stats_frame.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _barHeight = 5.0;

class SportsTeamStatsCard extends StatelessWidget {
  const SportsTeamStatsCard({
    super.key,
    required this.title,
    required this.rows,
    required this.homeName,
    required this.awayName,
    required this.colors,
    this.autofocus = false,
  });

  final String title;
  final List<SportsStatRow> rows;
  final String homeName;
  final String awayName;
  final ({Color home, Color away}) colors;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SportsStatsCard(
    title: title,
    children: [
      for (final (index, row) in rows.indexed)
        SportsStatsFocusRow(
          key: ValueKey('sports-stats-row-${row.label}'),
          autofocus: autofocus && index == 0,
          label:
              '${row.label}: $homeName ${row.homeText}, '
              '$awayName ${row.awayText}',
          child: _row(row),
        ),
    ],
  );

  Widget _row(SportsStatRow row) {
    final home = row.homeValue;
    final away = row.awayValue;
    final homeAhead = row.homeAhead == true;
    final awayAhead = row.homeAhead == false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Figures shrink to fit rather than overflow at large text sizes on
        // a narrow phone; the label gets the most room and wraps.
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _figure(
                row.homeText,
                ahead: homeAhead,
                alignment: AlignmentDirectional.centerStart,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Center(
                child: sportsLabelText(
                  row.label,
                  _tokens.fgDim,
                  size: 12,
                  weight: FontWeight.w600,
                  maxLines: 2,
                  ellipsize: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _figure(
                row.awayText,
                ahead: awayAhead,
                alignment: AlignmentDirectional.centerEnd,
              ),
            ),
          ],
        ),
        if (row.hasBars) ...[
          const SizedBox(height: 6),
          _bars(home!, away!, homeAhead: homeAhead, awayAhead: awayAhead),
        ],
      ],
    );
  }

  Widget _figure(
    String text, {
    required bool ahead,
    required AlignmentGeometry alignment,
  }) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: sportsLabelText(
      text,
      ahead ? _tokens.fg : _tokens.fgMid,
      size: 14,
      weight: ahead ? FontWeight.w700 : FontWeight.w500,
      tabular: true,
    ),
  );

  Widget _bars(
    double home,
    double away, {
    required bool homeAhead,
    required bool awayAhead,
  }) {
    final top = [home.abs(), away.abs()].reduce((a, b) => a > b ? a : b);
    double share(double value) => top <= 0 ? 0 : value.abs() / top;
    return Row(
      children: [
        Expanded(
          child: _Bar(
            share: share(home),
            color: homeAhead || !awayAhead
                ? colors.home
                : colors.home.withValues(alpha: 0.45),
            fromEnd: true,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _Bar(
            share: share(away),
            color: awayAhead || !homeAhead
                ? colors.away
                : colors.away.withValues(alpha: 0.45),
            fromEnd: false,
          ),
        ),
      ],
    );
  }
}

/// A track with [share] of it filled, from the middle of the row outwards.
class _Bar extends StatelessWidget {
  const _Bar({required this.share, required this.color, required this.fromEnd});

  final double share;
  final Color color;
  final bool fromEnd;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(_barHeight / 2),
    child: Container(
      height: _barHeight,
      color: _tokens.hairline,
      alignment: fromEnd
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: share.clamp(0.0, 1.0),
        heightFactor: 1,
        child: ColoredBox(color: color),
      ),
    ),
  );
}
