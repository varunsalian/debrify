// The featured fixture above the Sports board.
//
// Presentation layer. The hero renders the event the board picked (see
// `pickSportsHero`) with the watch options found for it, and reports its two
// intents — play the first guide channel, open the details — upward.
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_event_card.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

const _heroPreviewFlex = 13;
const _heroInfoFlex = 10;

/// The featured fixture: eyebrow, both teams at hero scale, live progress and
/// the two ways to act on it.
class SportsBoardHero extends StatelessWidget {
  const SportsBoardHero({
    super.key,
    required this.event,
    required this.watch,
    required this.hideScores,
    required this.wide,
    required this.onPlay,
    required this.onDetails,
  });

  final SportsEvent event;
  final SportsWatchOptions watch;
  final bool hideScores;

  /// Wide boards pair the info with a preview panel; narrow ones skip it.
  final bool wide;
  final void Function(SportsChannelRef channel) onPlay;
  final VoidCallback onDetails;

  SportsLeague? get _league => sportsLeagueById(event.leagueId);

  SportsWatchOption? get _firstGuide =>
      watch.guide.isEmpty ? null : watch.guide.first;

  /// Minutes of a live soccer clock over 90; anything unparseable hides the
  /// bar rather than guessing a position.
  double? get _progress {
    if (event.status != SportsEventStatus.live) return null;
    if (_league?.sport != SportKind.soccer) return null;
    final minutes = int.tryParse(
      RegExp(r'^(\d+)').firstMatch(event.clock?.trim() ?? '')?.group(1) ?? '',
    );
    if (minutes == null) return null;
    return (minutes / 90).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _tokens.panel,
      borderRadius: BorderRadius.circular(18),
    ),
    child: wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: _heroInfoFlex, child: _info()),
              const SizedBox(width: 16),
              Expanded(flex: _heroPreviewFlex, child: _preview()),
            ],
          )
        : _info(),
  );

  Widget _info() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsLabelText(
        '${_league?.name ?? event.leagueId} · '
        '${sportsEventStatusText(event)}',
        _tokens.accent,
        size: 11,
        weight: FontWeight.w700,
        tracking: 0.8,
        ellipsize: true,
      ),
      const SizedBox(height: 14),
      if (event.isTeamEvent) _matchup() else _titleBlock(),
      if (_progress case final progress?) ...[
        const SizedBox(height: 12),
        _progressBar(progress),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_firstGuide case final option?)
            SportsFocusPill.row(
              key: const ValueKey('sports-hero-play'),
              label: 'Watch on ${option.channel.name}',
              onPressed: () => onPlay(option.channel),
              builder: (_, ink, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 16, color: ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: sportsLabelText(
                      'Watch on '
                      '${sportsChannelDisplayName(option.channel.name)}',
                      ink,
                      weight: FontWeight.w700,
                      ellipsize: true,
                    ),
                  ),
                ],
              ),
            ),
          SportsFocusPill.row(
            key: const ValueKey('sports-hero-details'),
            label: 'Where to watch · ${watch.count}',
            onPressed: onDetails,
            builder: (_, ink, _) => sportsLabelText(
              'Where to watch · ${watch.count}',
              ink,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _matchup() => Row(
    children: [
      SportsTeamCrest(team: event.home!, size: 52),
      const SizedBox(width: 12),
      Expanded(
        child: sportsLabelText(
          event.home!.name,
          _tokens.fg,
          size: 16,
          weight: FontWeight.w700,
          ellipsize: true,
        ),
      ),
      const SizedBox(width: 12),
      _score(),
      const SizedBox(width: 12),
      Expanded(
        child: sportsLabelText(
          event.away!.name,
          _tokens.fg,
          size: 16,
          weight: FontWeight.w700,
          ellipsize: true,
        ),
      ),
      const SizedBox(width: 12),
      SportsTeamCrest(team: event.away!, size: 52),
    ],
  );

  Widget _score() {
    final home = event.homeScore;
    final away = event.awayScore;
    if (home == null || away == null) {
      return sportsLabelText(
        sportsMatchupConnector(_league?.sport),
        _tokens.fgFaint,
        size: 22,
        weight: FontWeight.w700,
      );
    }
    if (hideScores) {
      return sportsLabelText(
        hiddenScoresGlyph,
        _tokens.fgFaint,
        size: 22,
        tracking: 1,
      );
    }
    return sportsLabelText(
      '$home – $away',
      _tokens.fg,
      size: 30,
      weight: FontWeight.w700,
      tabular: true,
    );
  }

  Widget _titleBlock() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsLabelText(
        event.displayTitle,
        _tokens.fg,
        size: 22,
        weight: FontWeight.w700,
        height: 1.2,
        maxLines: 2,
        ellipsize: true,
      ),
      if ((event.subtitle ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: sportsLabelText(
            event.subtitle!,
            _tokens.fgDim,
            size: 12.5,
            ellipsize: true,
          ),
        ),
    ],
  );

  Widget _progressBar(double progress) => ClipRRect(
    key: const ValueKey('sports-hero-progress'),
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: _tokens.hairline2),
          FractionallySizedBox(
            widthFactor: progress,
            child: ColoredBox(color: _tokens.accent),
          ),
        ],
      ),
    ),
  );

  /// v1 has no live video here; the panel says which channel would carry it.
  Widget _preview() => AspectRatio(
    key: const ValueKey('sports-hero-preview'),
    aspectRatio: 16 / 9,
    child: Container(
      decoration: BoxDecoration(
        color: _tokens.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _tokens.hairline),
      ),
      alignment: Alignment.center,
      child: sportsLabelText(
        _firstGuide == null
            ? 'No channel in your guide'
            : sportsChannelDisplayName(_firstGuide!.channel.name),
        _tokens.fgFaint,
        size: 13,
        weight: FontWeight.w600,
        ellipsize: true,
      ),
    ),
  );
}
