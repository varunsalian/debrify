// One fixture on the sports board.
//
// Presentation layer. [SportsEventCard] renders an immutable [SportsEvent]
// together with the watch options found for it and reports a single intent
// through [onPressed]; the board decides what opening a card means. It is a
// [SportsFocusPill] in the card style, so focus, activation and semantics are
// the same contract the details panel's rows have. Every shape shares one
// frame — header (league or series, format badge, time / live clock / FT),
// the shape's body from [SportsEventCardBody], and the channel footer — and
// one fixed height, so cards line up in the board's grid. All colours are the
// Spotlight tokens.
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sports_event_card_bodies.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// Stand-in for a score the user chose to hide (the hero; cards draw a bar).
const hiddenScoresGlyph = '···';

/// A card's height at the default text size: the tallest body (golf with a
/// leader, cricket with a match note) plus the header and footer.
const _cardExtent = 178.0;

/// The fixed card height the board's grid uses, grown with the text scale so
/// larger text never clips a card.
double sportsEventCardHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(_cardExtent);

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

/// A fixture card: header, the shape's body, and where to watch it.
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
    this.width,
    this.now,
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

  /// Null fills the grid cell.
  final double? width;

  /// The board's "now", so a kick-off reads "today" exactly when the day
  /// headings do; null reads the wall clock.
  final DateTime? now;

  String get _leagueName =>
      sportsLeagueById(event.leagueId)?.name ?? event.leagueId;

  SportsEventShape get _shape => sportsCardShapeOf(event);

  /// Series or tournament first, then a fight card's own name, then the
  /// league.
  String get _headerName {
    final group = (event.group ?? '').trim();
    if (group.isNotEmpty) return group;
    if (_shape == SportsEventShape.card) {
      final (card, _) = sportsFightCardTitle(event.displayTitle);
      if (card != null) return card;
    }
    return _leagueName;
  }

  /// A fight card names its weight class in the body instead.
  String? get _badge {
    final format = (event.format ?? '').trim();
    if (format.isEmpty || _shape == SportsEventShape.card) return null;
    return format;
  }

  /// The footer, as the plain sentence the card paints.
  String get _watchText {
    final guide = watch.guide;
    if (guide.isNotEmpty) {
      final name = sportsChannelDisplayName(guide.first.channel.name);
      final extra = guide.length - 1;
      return extra > 0 ? '$name +$extra' : name;
    }
    if (watch.possible.isNotEmpty) return '${watch.possible.length} possible';
    return 'Not on your channels yet';
  }

  /// The whole card is one control, so the sentence a screen reader needs is
  /// built here rather than from the painted text runs.
  String get _semanticLabel => <String>[
    if (followed) 'Followed',
    _leagueName,
    if ((event.group ?? '').trim().isNotEmpty) event.group!.trim(),
    event.displayTitle,
    sportsEventStatusText(event, now: now),
    ?_badge,
    _watchText,
  ].join(', ');

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: sportsEventCardHeight(context),
    child: SportsFocusPill(
      label: _semanticLabel,
      style: event.status == SportsEventStatus.live
          ? _liveCardStyle
          : _cardStyle,
      selected: followed,
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
      builder: (context, ink, subtle) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: SportsEventCardBody(
                  event: event,
                  hideScores: hideScores,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _footer(),
        ],
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: sportsLabelText(
                _headerName,
                _tokens.accent,
                size: 11.5,
                weight: FontWeight.w700,
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
            if (_badge case final badge?) ...[
              const SizedBox(width: 8),
              _formatBadge(badge),
            ],
          ],
        ),
      ),
      const SizedBox(width: 8),
      _status(),
    ],
  );

  Widget _formatBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: _tokens.hairline2),
      borderRadius: BorderRadius.circular(6),
    ),
    child: sportsLabelText(
      text,
      _tokens.fgDim,
      size: 10,
      weight: FontWeight.w600,
      tabular: true,
    ),
  );

  Widget _status() {
    if (event.status == SportsEventStatus.live) {
      final clock = event.clock?.trim() ?? '';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SportsLiveDot(),
          const SizedBox(width: 6),
          sportsLabelText(
            clock.isEmpty ? 'LIVE' : clock,
            _tokens.rec,
            size: 11.5,
            weight: FontWeight.w700,
            tabular: true,
          ),
        ],
      );
    }
    final color = switch (event.status) {
      SportsEventStatus.postponed => _tokens.rec,
      SportsEventStatus.finished => _tokens.fgDim,
      _ => _tokens.fg,
    };
    return sportsLabelText(
      sportsEventStatusText(event, now: now),
      color,
      size: 11.5,
      weight: FontWeight.w700,
      tabular: true,
    );
  }

  Widget _footer() {
    final guide = watch.guide;
    final Widget content;
    if (guide.isNotEmpty) {
      final extra = guide.length - 1;
      content = Row(
        children: [
          Icon(Icons.live_tv_rounded, size: 14, color: _tokens.live),
          const SizedBox(width: 8),
          Expanded(
            child: sportsLabelText(
              sportsChannelDisplayName(guide.first.channel.name),
              _tokens.live,
              size: 12,
              weight: FontWeight.w600,
              ellipsize: true,
            ),
          ),
          if (extra > 0)
            sportsLabelText('+$extra', _tokens.fgDim, size: 11, tabular: true),
        ],
      );
    } else if (watch.possible.isNotEmpty) {
      content = Row(
        children: [
          Icon(Icons.live_tv_outlined, size: 14, color: _tokens.fgDim),
          const SizedBox(width: 8),
          Expanded(
            child: sportsLabelText(
              _watchText,
              _tokens.fgDim,
              size: 12,
              ellipsize: true,
            ),
          ),
        ],
      );
    } else {
      content = sportsLabelText(
        _watchText,
        _tokens.fgFaint,
        size: 12,
        ellipsize: true,
      );
    }
    return Container(
      padding: const EdgeInsets.only(top: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _tokens.hairline)),
      ),
      child: content,
    );
  }
}

/// The red dot that marks live play, with its soft halo.
class SportsLiveDot extends StatelessWidget {
  const SportsLiveDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: _tokens.rec,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: _tokens.rec.withValues(alpha: 0.14), spreadRadius: 3),
      ],
    ),
  );
}

/// The board card ramp ([SportsFocusPillStyle.card]) with an edge at rest:
/// a hairline, or red while the fixture is live.
SportsFocusPillStyle _cardStyleWith(Color restBorder) {
  const card = SportsFocusPillStyle.card;
  return SportsFocusPillStyle(
    radius: card.radius,
    restColor: card.restColor,
    hoverColor: card.hoverColor,
    focusedFill: card.focusedFill,
    focusedBorderColor: card.focusedBorderColor,
    focusedBorderWidth: card.focusedBorderWidth,
    glow: card.glow,
    scale: card.scale,
    invertInkOnFocus: card.invertInkOnFocus,
    restBorderColor: restBorder,
  );
}

final _cardStyle = _cardStyleWith(_tokens.hairline);
final _liveCardStyle = _cardStyleWith(_tokens.rec.withValues(alpha: 0.45));
