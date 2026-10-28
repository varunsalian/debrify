// One fixture on the sports board.
//
// Presentation layer. [SportsEventCard] renders an immutable [SportsEvent]
// together with the watch options found for it and reports a single intent
// through [onPressed]; the board decides what opening a card means. It is a
// [SportsFocusPill] in the card style, so focus, activation and semantics are
// the same contract the details panel's rows have. All colours are the
// Spotlight tokens.
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// Stand-in for a score the user chose to hide.
const hiddenScoresGlyph = '···';

/// The status string a card shows, reused verbatim by the details header.
///
/// [now] exists so tests can pin the "is this today" decision; production
/// leaves it null and reads the wall clock.
String sportsEventStatusText(SportsEvent event, {DateTime? now}) {
  final label = event.statusLabel.trim();
  final clock = event.clock?.trim() ?? '';
  return switch (event.status) {
    SportsEventStatus.live => clock.isEmpty ? 'LIVE' : 'LIVE $clock',
    SportsEventStatus.finished => label.isEmpty ? 'FT' : label,
    SportsEventStatus.postponed => 'Postponed',
    SportsEventStatus.scheduled => _kickoffText(
      event.start,
      now ?? DateTime.now(),
    ),
  };
}

/// Local `HH:mm`, prefixed with the weekday once the fixture is not today.
String _kickoffText(DateTime startUtc, DateTime now) {
  final local = startUtc.toLocal();
  final time = DateFormat('HH:mm').format(local);
  final day = DateFormat('yyyy-MM-dd');
  if (day.format(local) == day.format(now.toLocal())) return time;
  return '${DateFormat('EEE').format(local)} $time';
}

/// `'UK: Sky Sports Main Event FHD'` → `'Sky Sports Main Event'`.
///
/// The comparison-ready base name (region tag and quality tokens dropped) is
/// lower case by construction, so the display form capitalizes each word.
String sportsChannelDisplayName(String channelName) {
  final base = channelBaseName(channelName);
  if (base.isEmpty) return channelName.trim();
  return base
      .split(' ')
      .map(
        (word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
}

/// The word between two competitors, as the board and the panel both read it.
///
/// North-American leagues say `'Knicks at Celtics'`; the rest of the catalog
/// has no home/away order to speak of and reads `'Arsenal v Chelsea'`.
String sportsMatchupConnector(SportKind? sport) => switch (sport) {
  SportKind.basketball ||
  SportKind.americanFootball ||
  SportKind.hockey ||
  SportKind.baseball => 'at',
  _ => 'v',
};

/// A fixture row: league, status, both teams with scores, where to watch.
class SportsEventCard extends StatelessWidget {
  const SportsEventCard({
    super.key,
    required this.event,
    required this.hideScores,
    required this.followed,
    required this.watch,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.width = 236,
  });

  final SportsEvent event;

  /// Hides scores without hiding the fixture.
  final bool hideScores;

  /// The user follows this event's league or one of its teams.
  final bool followed;

  final SportsWatchOptions watch;
  final VoidCallback onPressed;

  /// Supplied by the board so focus survives a rebuild; owned by the pill
  /// otherwise.
  final FocusNode? focusNode;

  final bool autofocus;
  final double width;

  String get _leagueShortName =>
      sportsLeagueById(event.leagueId)?.shortName ?? event.leagueId;

  /// The bottom badge, as the plain sentence the card paints.
  String get _watchText {
    final guide = watch.guide;
    if (guide.isNotEmpty) {
      final name = sportsChannelDisplayName(guide.first.channel.name);
      final extra = guide.length - 1;
      return extra > 0 ? '$name +$extra' : name;
    }
    if (watch.possible.isNotEmpty) return '${watch.possible.length} possible';
    return 'No listing yet';
  }

  /// The whole card is one control, so the sentence a screen reader needs is
  /// built here rather than from the painted text runs.
  String get _semanticLabel => <String>[
    if (followed) 'Followed',
    sportsLeagueById(event.leagueId)?.name ?? event.leagueId,
    event.displayTitle,
    sportsEventStatusText(event),
    _watchText,
  ].join(', ');

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: SportsFocusPill(
      label: _semanticLabel,
      style: SportsFocusPillStyle.card,
      selected: followed,
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      padding: const EdgeInsets.all(12),
      builder: (context, ink, subtle) => _body(),
    ),
  );

  Widget _body() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _topRow(),
      const SizedBox(height: 10),
      if (event.isTeamEvent) ..._teamRows() else _title(),
      const SizedBox(height: 2),
      Container(
        height: 1,
        color: _tokens.hairline,
        margin: const EdgeInsets.only(bottom: 8),
      ),
      _watchBadge(),
    ],
  );

  Widget _topRow() => Row(
    children: [
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: sportsLabelText(
                _leagueShortName,
                _tokens.accent,
                size: 11,
                weight: FontWeight.w700,
                tracking: 0.6,
                ellipsize: true,
              ),
            ),
            if (followed)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.star_rounded,
                  size: 12,
                  color: _tokens.accent,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 6),
      _status(),
    ],
  );

  Widget _status() {
    final color = switch (event.status) {
      SportsEventStatus.live => _tokens.live,
      SportsEventStatus.postponed => _tokens.rec,
      SportsEventStatus.finished => _tokens.fgDim,
      SportsEventStatus.scheduled => _tokens.fgMid,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (event.status == SportsEventStatus.live) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _tokens.live,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
        ],
        sportsLabelText(
          sportsEventStatusText(event),
          color,
          size: 11,
          weight: FontWeight.w700,
          tracking: 0.3,
        ),
      ],
    );
  }

  List<Widget> _teamRows() => [
    _teamRow(event.home, event.homeScore),
    _teamRow(event.away, event.awayScore),
  ];

  Widget _teamRow(SportsTeam? team, int? score) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SportsTeamCrest(team: team!, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: sportsLabelText(
            team.name,
            _tokens.fg,
            size: 13.5,
            weight: FontWeight.w600,
            ellipsize: true,
          ),
        ),
        if (score != null && hideScores)
          sportsLabelText(
            hiddenScoresGlyph,
            _tokens.fgFaint,
            size: 11,
            tracking: 1,
          )
        else if (score != null)
          sportsLabelText(
            '$score',
            _tokens.fg,
            size: 15,
            weight: FontWeight.w700,
            tabular: true,
          ),
      ],
    ),
  );

  Widget _title() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsLabelText(
        event.displayTitle,
        _tokens.fg,
        size: 14,
        weight: FontWeight.w700,
        maxLines: 2,
        ellipsize: true,
      ),
      if ((event.subtitle ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: sportsLabelText(
            event.subtitle!,
            _tokens.fgDim,
            size: 11.5,
            ellipsize: true,
          ),
        ),
    ],
  );

  Widget _watchBadge() {
    final guide = watch.guide;
    if (guide.isEmpty) {
      final color = watch.isEmpty ? _tokens.fgFaint : _tokens.fgDim;
      return sportsLabelText(_watchText, color, size: 11.5, ellipsize: true);
    }
    final extra = guide.length - 1;
    return Row(
      children: [
        Icon(Icons.check_rounded, size: 12, color: _tokens.live),
        const SizedBox(width: 5),
        Expanded(
          child: sportsLabelText(
            sportsChannelDisplayName(guide.first.channel.name),
            _tokens.fgMid,
            size: 11.5,
            ellipsize: true,
          ),
        ),
        if (extra > 0)
          sportsLabelText(
            '+$extra',
            _tokens.live,
            size: 11.5,
            weight: FontWeight.w700,
          ),
      ],
    );
  }
}
