// The middle of a board card, one layout per [SportsEventShape].
//
// Presentation layer. Each body paints an immutable [SportsEvent] and nothing
// else: the card frame owns the header, the footer, focus and semantics. Every
// score respects the Scores toggle, and a hidden result also keeps the loser
// undimmed and the match situation unsaid, because both give the result away.
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _sideGap = 8.0;

/// The shape a card for [event] uses. Unknown leagues and team shapes that
/// arrive without both sides fall back to the title layout.
SportsEventShape sportsCardShapeOf(SportsEvent event) {
  final league = sportsLeagueById(event.leagueId);
  final shape = league == null
      ? (event.isTeamEvent ? SportsEventShape.teams : SportsEventShape.event)
      : sportsEventShapeOf(league);
  final needsSides =
      shape == SportsEventShape.teams ||
      shape == SportsEventShape.innings ||
      shape == SportsEventShape.sets;
  return needsSides && !event.isTeamEvent ? SportsEventShape.event : shape;
}

/// `'UFC Fight Night: Moicano vs. Nolan'` → `('UFC Fight Night', 'Moicano vs.
/// Nolan')`; a title without a colon has no card name.
(String?, String) sportsFightCardTitle(String title) {
  final split = title.indexOf(': ');
  if (split <= 0 || split + 2 >= title.length) return (null, title);
  return (title.substring(0, split), title.substring(split + 2));
}

/// Where a score would be, while the user keeps scores hidden.
class SportsHiddenScore extends StatelessWidget {
  const SportsHiddenScore({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 10,
    decoration: BoxDecoration(
      color: _tokens.hairline2,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// The card body for [event] in its [sportsCardShapeOf] layout.
class SportsEventCardBody extends StatelessWidget {
  const SportsEventCardBody({
    super.key,
    required this.event,
    required this.hideScores,
  });

  final SportsEvent event;
  final bool hideScores;

  bool get _finished => event.status == SportsEventStatus.finished;

  /// Who won, only while the result may be shown.
  bool? get _homeWon {
    if (!_finished || hideScores) return null;
    if (event.homeWon != null) return event.homeWon;
    final home = event.homeScore;
    final away = event.awayScore;
    if (home == null || away == null || home == away) return null;
    return home > away;
  }

  @override
  Widget build(BuildContext context) => switch (sportsCardShapeOf(event)) {
    SportsEventShape.teams => _sides(
      (team) => SportsTeamCrest(team: team, size: 26),
      _numberScore(event.homeScore),
      _numberScore(event.awayScore),
    ),
    SportsEventShape.innings => _innings(),
    SportsEventShape.sets => _sides(
      (team) => SportsFlagPlate(team: team),
      _sets(event.homeLines),
      _sets(event.awayLines),
    ),
    SportsEventShape.card => _fightCard(),
    SportsEventShape.event => _titled(),
  };

  Widget _sides(
    Widget Function(SportsTeam team) art,
    Widget? homeScore,
    Widget? awayScore,
  ) {
    final won = _homeWon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _side(event.home!, art, homeScore, loser: won == false),
        const SizedBox(height: _sideGap),
        _side(event.away!, art, awayScore, loser: won == true),
      ],
    );
  }

  Widget _side(
    SportsTeam team,
    Widget Function(SportsTeam team) art,
    Widget? score, {
    required bool loser,
  }) => SizedBox(
    height: 26,
    child: Row(
      children: [
        SizedBox(width: 26, child: Center(child: art(team))),
        const SizedBox(width: 10),
        Expanded(
          child: sportsLabelText(
            team.name,
            loser ? _tokens.fgDim : _tokens.fg,
            size: 14.5,
            weight: loser ? FontWeight.w500 : FontWeight.w600,
            ellipsize: true,
          ),
        ),
        if (score != null) ...[const SizedBox(width: 10), score],
      ],
    ),
  );

  Widget? _numberScore(int? score) {
    if (score == null) return null;
    if (hideScores) return const SportsHiddenScore();
    return sportsLabelText(
      '$score',
      _tokens.fg,
      size: 15,
      weight: FontWeight.w600,
      tabular: true,
    );
  }

  Widget? _textScore(String? text, int? number) {
    final score = (text ?? '').trim().isNotEmpty
        ? text!.trim()
        : number?.toString();
    if (score == null) return null;
    if (hideScores) return const SportsHiddenScore();
    return sportsLabelText(
      score,
      _tokens.fg,
      size: 13,
      weight: FontWeight.w600,
      tabular: true,
    );
  }

  /// Games per set; the last (current or deciding) set in full ink.
  Widget? _sets(List<int> lines) {
    if (lines.isEmpty) return null;
    if (hideScores) return const SportsHiddenScore();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, games) in lines.indexed) ...[
          if (index > 0) const SizedBox(width: 6),
          sportsLabelText(
            '$games',
            index == lines.length - 1 ? _tokens.fg : _tokens.fgDim,
            size: 13,
            weight: index == lines.length - 1
                ? FontWeight.w600
                : FontWeight.w400,
            tabular: true,
          ),
        ],
      ],
    );
  }

  Widget _innings() {
    final note = (event.note ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sides(
          (team) => SportsTeamCrest(team: team, size: 26),
          _textScore(event.homeScoreText, event.homeScore),
          _textScore(event.awayScoreText, event.awayScore),
        ),
        if (note.isNotEmpty && !hideScores) ...[
          const SizedBox(height: 6),
          _sub(note, maxLines: 1),
        ],
      ],
    );
  }

  Widget _fightCard() {
    final (_, title) = sportsFightCardTitle(event.displayTitle);
    final format = (event.format ?? '').trim();
    final bouts = event.itemCount;
    final summary = [
      if (format.isNotEmpty) '$format main event',
      if (bouts != null && bouts > 0) '$bouts ${bouts == 1 ? 'bout' : 'bouts'}',
    ].join(' · ');
    final venue = (event.subtitle ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _big(title),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          _sub(summary, maxLines: 1),
        ],
        if (venue.isNotEmpty) _sub(venue, maxLines: 1),
      ],
    );
  }

  Widget _titled() {
    final venue = (event.subtitle ?? '').trim();
    final leader = (event.leaderName ?? '').trim();
    final leaderScore = (event.leaderScore ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _big(event.displayTitle),
        if (venue.isNotEmpty) ...[
          const SizedBox(height: 4),
          _sub(venue, maxLines: leader.isEmpty ? 2 : 1),
        ],
        if (leader.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _sub('Leader · $leader', maxLines: 1)),
              if (leaderScore.isNotEmpty) ...[
                const SizedBox(width: 10),
                if (hideScores)
                  const SportsHiddenScore()
                else
                  sportsLabelText(
                    leaderScore,
                    _tokens.fg,
                    size: 12.5,
                    weight: FontWeight.w600,
                    tabular: true,
                  ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _big(String text) => sportsLabelText(
    text,
    _tokens.fg,
    size: 15,
    weight: FontWeight.w700,
    height: 1.3,
    maxLines: 2,
    ellipsize: true,
  );

  Widget _sub(String text, {required int maxLines}) => sportsLabelText(
    text,
    _tokens.fgDim,
    size: 12.5,
    height: 1.4,
    maxLines: maxLines,
    ellipsize: true,
  );
}
