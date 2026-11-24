// Recent form: each side's last games, oldest first, as a result chip with
// the score and the opponent.
//
// Presentation layer. The card is one D-pad stop: it is short enough to sit
// on screen whole, and a reader hears both sides' run as one sentence each.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_stats_frame.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _win = Color(0xFF30D158);
const _loss = Color(0xFFFF453A);
const _draw = Color(0xFF8E8E93);

/// Narrower than this, the two sides stack.
const _sideBySideMinWidth = 420.0;

class SportsFormCard extends StatelessWidget {
  const SportsFormCard({
    super.key,
    required this.stats,
    required this.colors,
    this.autofocus = false,
  });

  final SportsMatchStats stats;
  final ({Color home, Color away}) colors;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SportsStatsCard(
    title: 'Recent form',
    children: [
      SportsStatsFocusRow(
        autofocus: autofocus,
        label: [
          _spoken(stats.home, stats.homeForm),
          _spoken(stats.away, stats.awayForm),
        ].join('. '),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final home = _column(stats.home, stats.homeForm, colors.home);
            final away = _column(stats.away, stats.awayForm, colors.away);
            // A phone stacks the sides so each run keeps a full line.
            if (constraints.maxWidth < _sideBySideMinWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [home, const SizedBox(height: 10), away],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: home),
                const SizedBox(width: 12),
                Expanded(child: away),
              ],
            );
          },
        ),
      ),
    ],
  );

  static String _spoken(SportsMatchSide side, List<SportsFormGame> games) {
    if (games.isEmpty) return '${side.name}: no recent games';
    final runs = [
      for (final game in games)
        '${_word(game.result)} ${game.score} '
            '${game.home ? 'versus' : 'at'} ${game.opponentAbbreviation}',
    ];
    return '${side.name} last ${games.length}: ${runs.join(', ')}';
  }

  static String _word(SportsFormResult result) => switch (result) {
    SportsFormResult.win => 'won',
    SportsFormResult.loss => 'lost',
    SportsFormResult.draw => 'drew',
  };

  Widget _column(SportsMatchSide side, List<SportsFormGame> games, Color tint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SportsTeamCrest(
              team: SportsTeam(
                id: side.teamId,
                name: side.name,
                shortName: side.name,
                abbreviation: side.abbreviation,
                logoUrl: side.logoUrl,
                color: side.color,
              ),
              size: 22,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: sportsLabelText(
                side.abbreviation,
                tint,
                weight: FontWeight.w700,
                ellipsize: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (games.isEmpty)
          sportsLabelText('No recent games', _tokens.fgFaint, size: 12)
        else
          for (final game in games) _game(game),
      ],
    );
  }

  Widget _game(SportsFormGame game) {
    final (letter, color) = switch (game.result) {
      SportsFormResult.win => ('W', _win),
      SportsFormResult.loss => ('L', _loss),
      SportsFormResult.draw => ('D', _draw),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: sportsLabelText(
              letter,
              color,
              size: 11,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            flex: 3,
            child: sportsLabelText(
              game.score,
              _tokens.fg,
              size: 12.5,
              weight: FontWeight.w600,
              tabular: true,
              ellipsize: true,
            ),
          ),
          const SizedBox(width: 6),
          sportsLabelText(game.home ? 'vs' : '@', _tokens.fgFaint, size: 11),
          const SizedBox(width: 4),
          if (game.opponentLogoUrl case final logo?) ...[
            _OpponentLogo(url: logo),
            const SizedBox(width: 4),
          ],
          Flexible(
            flex: 2,
            child: sportsLabelText(
              game.opponentAbbreviation,
              _tokens.fgMid,
              size: 12,
              weight: FontWeight.w600,
              ellipsize: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// The opponent's logo, or nothing while it is missing: the abbreviation
/// beside it already names the team.
class _OpponentLogo extends StatelessWidget {
  const _OpponentLogo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 16,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        memCacheHeight: (16 * MediaQuery.devicePixelRatioOf(context)).round(),
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}
