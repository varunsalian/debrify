// The body of the match stats page: which cards a match gets and how they sit
// on the screen.
//
// Presentation layer. Cards appear only for sections the feed sent. A wide
// screen (desktop, TV, tablet landscape) gets two columns — probability and
// team stats on the left, leaders and form on the right — a narrow one a
// single column in the same reading order.
import 'package:debrify/features/sports/application/sports_match_stat_rows.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/material.dart';

import 'sports_form_card.dart';
import 'sports_leaders_card.dart';
import 'sports_stats_frame.dart';
import 'sports_team_stats_card.dart';
import 'sports_win_probability_card.dart';

/// Content narrower than this stacks into one column.
const double sportsStatsTwoColumnMinWidth = 760;
const double _gap = 14;

class SportsMatchStatsSections extends StatelessWidget {
  const SportsMatchStatsSections({
    super.key,
    required this.stats,
    required this.sport,
  });

  final SportsMatchStats stats;
  final SportKind sport;

  @override
  Widget build(BuildContext context) {
    final colors = sportsStatsColors(stats.home, stats.away);
    final preview = stats.isPreview;
    final rows = sportsStatRows(sport, stats.teamStats, season: preview);
    final hasForm = stats.homeForm.isNotEmpty || stats.awayForm.isNotEmpty;
    // Only the first card claims the opening focus.
    var focusClaimed = false;
    bool claim() {
      if (focusClaimed) return false;
      return focusClaimed = true;
    }

    final probability = stats.hasWinProbability
        ? SportsWinProbabilityCard(
            key: const ValueKey('sports-stats-probability'),
            stats: stats,
            colors: colors,
            autofocus: claim(),
          )
        : null;
    final teamStats = rows.isEmpty
        ? null
        : SportsTeamStatsCard(
            key: const ValueKey('sports-stats-team'),
            title: preview ? 'Season averages' : 'Team stats',
            rows: rows,
            homeName: stats.home.name,
            awayName: stats.away.name,
            colors: colors,
            autofocus: claim(),
          );
    final leaders = stats.leaders.isEmpty
        ? null
        : SportsLeadersCard(
            key: const ValueKey('sports-stats-leaders'),
            title: preview ? 'Season leaders' : 'Game leaders',
            leaders: stats.leaders,
            homeName: stats.home.name,
            awayName: stats.away.name,
            colors: colors,
            autofocus: claim(),
          );
    final form = hasForm
        ? SportsFormCard(
            key: const ValueKey('sports-stats-form'),
            stats: stats,
            colors: colors,
            autofocus: claim(),
          )
        : null;

    final left = [?probability, ?teamStats];
    final right = [?leaders, ?form];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= sportsStatsTwoColumnMinWidth &&
            left.isNotEmpty &&
            right.isNotEmpty;
        if (!wide) return _column([...left, ...right]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _column(left)),
            const SizedBox(width: _gap),
            Expanded(child: _column(right)),
          ],
        );
      },
    );
  }

  Widget _column(List<Widget> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, card) in cards.indexed) ...[
        if (index > 0) const SizedBox(height: _gap),
        card,
      ],
    ],
  );
}
