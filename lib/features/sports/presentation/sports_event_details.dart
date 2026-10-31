// The "where can I watch this" panel behind a board card.
//
// Presentation layer. It owns nothing but the pop result: selecting a row pops
// the route with its [SportsChannelRef] and the caller plays it once the route
// is gone, so a long guide list can never stay open behind the player. Follow
// labels toggle locally on tap and report the same intent upward, because the
// board's follow state reaches this route as a snapshot it cannot re-read.
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'sports_event_card.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _panelWidth = 420.0;
const _wideLayoutMinWidth = 640.0;
const _rowHeight = 52.0;
const _sheetHeightFactor = 0.88;

/// Shown when neither the guide nor a listed broadcaster has the fixture.
const noListingCopy =
    'No channel in your guide lists this match yet. Listings usually appear '
    'a day or two before kick-off.';

/// Subtitle on a possible-channel row: the feed named it, the guide did not.
const possibleChannelCopy = 'Listed broadcaster — not confirmed in your guide';

/// Subtitle on a channel whose own name is this match (an event stream).
const namedChannelCopy = 'Named for this match';

/// Opens the details for [event]: a 420 px panel docked right on wide screens,
/// a bottom sheet capped at 88 % of the height on narrow ones.
///
/// [onPlay] runs after the panel has closed, never underneath it.
Future<void> showSportsEventDetails(
  BuildContext context, {
  required SportsEvent event,
  required SportsWatchOptions watch,
  required SportsFollows follows,
  required void Function(SportsChannelRef) onPlay,
  required void Function(String teamKey) onToggleTeam,
  required void Function(String leagueId) onToggleLeague,
}) async {
  final surface = _DetailsSurface(
    event: event,
    watch: watch,
    follows: follows,
    onToggleTeam: onToggleTeam,
    onToggleLeague: onToggleLeague,
  );
  final wide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;
  final chosen = wide
      ? await _showPanel(context, surface)
      : await _showSheet(context, surface);
  if (chosen != null) onPlay(chosen);
}

Future<SportsChannelRef?> _showPanel(BuildContext context, Widget surface) =>
    showGeneralDialog<SportsChannelRef>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close event details',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          key: const ValueKey('sports-details-panel'),
          width: _panelWidth,
          height: double.infinity,
          child: surface,
        ),
      ),
      transitionBuilder: (_, animation, _, child) => Transform.translate(
        offset: Offset(
          _panelWidth * (1 - Curves.easeOutCubic.transform(animation.value)),
          0,
        ),
        child: child,
      ),
    );

Future<SportsChannelRef?> _showSheet(BuildContext context, Widget surface) =>
    showModalBottomSheet<SportsChannelRef>(
      context: context,
      isScrollControlled: true,
      barrierLabel: 'Close event details',
      backgroundColor: _tokens.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => ConstrainedBox(
        key: const ValueKey('sports-details-sheet'),
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(sheetContext).height * _sheetHeightFactor,
        ),
        child: surface,
      ),
    );

class _DetailsSurface extends StatefulWidget {
  const _DetailsSurface({
    required this.event,
    required this.watch,
    required this.follows,
    required this.onToggleTeam,
    required this.onToggleLeague,
  });

  final SportsEvent event;
  final SportsWatchOptions watch;
  final SportsFollows follows;
  final void Function(String teamKey) onToggleTeam;
  final void Function(String leagueId) onToggleLeague;

  @override
  State<_DetailsSurface> createState() => _DetailsSurfaceState();
}

class _DetailsSurfaceState extends State<_DetailsSurface> {
  final Set<String> _teamKeys = {};
  final Set<String> _leagueIds = {};
  final _timeFormat = DateFormat('HH:mm');

  /// Reset per build: only the first focusable control claims autofocus.
  bool _focusClaimed = false;

  SportsEvent get _event => widget.event;

  SportsLeague? get _league => sportsLeagueById(_event.leagueId);

  @override
  void initState() {
    super.initState();
    _teamKeys.addAll(widget.follows.teamKeys);
    _leagueIds.addAll(widget.follows.leagueIds);
  }

  bool _claimFocus() {
    if (_focusClaimed) return false;
    _focusClaimed = true;
    return true;
  }

  void _play(SportsChannelRef channel) => Navigator.of(context).pop(channel);

  void _toggleTeam(SportsTeam team) {
    final key = team.keyIn(_event.leagueId);
    setState(() => _flip(_teamKeys, key));
    widget.onToggleTeam(key);
  }

  void _toggleLeague() {
    setState(() => _flip(_leagueIds, _event.leagueId));
    widget.onToggleLeague(_event.leagueId);
  }

  static void _flip(Set<String> keys, String key) {
    if (!keys.remove(key)) keys.add(key);
  }

  /// Back / Escape closes the panel; a remote's Back button arrives as either
  /// key depending on the platform, and both must land on the same pop.
  KeyEventResult _onBackKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final back =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack;
    if (!back) return KeyEventResult.ignored;
    Navigator.of(context).pop();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _focusClaimed = false;
    final guide = widget.watch.guide;
    final possible = widget.watch.possible;
    final rows = <Widget>[_header(), const SizedBox(height: 16), _matchup()];
    // Guide listings first, then event streams found by their own name:
    // on the user's channels, but not in their guide.
    for (final (kind, title) in const [
      (SportsMatchKind.guide, 'In your guide'),
      (SportsMatchKind.channelName, 'On your channels'),
    ]) {
      final options = [
        for (final option in guide)
          if (option.kind == kind) option,
      ];
      if (options.isEmpty) continue;
      rows.add(_sectionTitle(title, tick: true));
      for (final option in options) {
        rows.add(_channelRow(option, autofocus: _claimFocus()));
      }
    }
    if (possible.isNotEmpty) {
      rows.add(_sectionTitle('Possible channels'));
      for (final option in possible) {
        rows.add(_channelRow(option, autofocus: _claimFocus()));
      }
    }
    if (guide.isEmpty && possible.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: sportsLabelText(
            noListingCopy,
            _tokens.fgDim,
            height: 1.45,
            maxLines: 4,
          ),
        ),
      );
    }
    rows
      ..add(const SizedBox(height: 18))
      ..add(_followButtons(autofocus: _claimFocus()))
      ..add(const SizedBox(height: 10))
      ..add(
        SportsFocusPill.row(
          key: const ValueKey('sports-details-close'),
          label: 'Close',
          autofocus: _claimFocus(),
          onPressed: () => Navigator.of(context).pop(),
          builder: (_, ink, _) => Center(
            child: sportsLabelText('Close', ink, weight: FontWeight.w700),
          ),
        ),
      );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onBackKey,
      child: Material(
        color: _tokens.panel,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      Expanded(
        child: sportsLabelText(
          _league?.name ?? _event.leagueId,
          _tokens.accent,
          size: 12,
          weight: FontWeight.w700,
          tracking: 0.7,
          maxLines: 2,
          ellipsize: true,
        ),
      ),
      const SizedBox(width: 8),
      sportsLabelText(
        sportsEventStatusText(_event),
        _tokens.fgDim,
        size: 12,
        weight: FontWeight.w600,
      ),
    ],
  );

  Widget _matchup() {
    if (!_event.isTeamEvent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sportsLabelText(
            _event.displayTitle,
            _tokens.fg,
            size: 20,
            weight: FontWeight.w700,
            height: 1.2,
            maxLines: 3,
          ),
          if ((_event.subtitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: sportsLabelText(
                _event.subtitle!,
                _tokens.fgDim,
                size: 12.5,
                ellipsize: true,
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _teamRow(_event.home!, _event.homeScore),
        _teamRow(_event.away!, _event.awayScore),
        // North-American leagues read "Knicks at Celtics"; the rest read "v".
        if (_event.homeScore == null || _event.awayScore == null)
          sportsLabelText(
            sportsMatchupConnector(_league?.sport),
            _tokens.fgFaint,
            size: 12,
            weight: FontWeight.w700,
            tracking: 0.6,
          ),
      ],
    );
  }

  Widget _teamRow(SportsTeam team, int? score) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        SportsTeamCrest(team: team, size: 36),
        const SizedBox(width: 11),
        Expanded(
          child: sportsLabelText(
            team.name,
            _tokens.fg,
            size: 16,
            weight: FontWeight.w600,
            height: 1.2,
            maxLines: 2,
            ellipsize: true,
          ),
        ),
        if (score != null)
          sportsLabelText(
            '$score',
            _tokens.fg,
            size: 24,
            weight: FontWeight.w700,
            tabular: true,
          ),
      ],
    ),
  );

  Widget _sectionTitle(String title, {bool tick = false}) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 7),
    child: Row(
      children: [
        if (tick) ...[
          Icon(Icons.check_rounded, size: 14, color: _tokens.live),
          const SizedBox(width: 6),
        ],
        sportsLabelText(
          title,
          _tokens.fgDim,
          size: 11.5,
          weight: FontWeight.w700,
          tracking: 1.1,
        ),
      ],
    ),
  );

  /// One channel: guide options are solid rows ending in "Watch", possible
  /// ones are outlined and end in "Open".
  Widget _channelRow(SportsWatchOption option, {required bool autofocus}) {
    final channel = option.channel;
    final listing = option.listing;
    final confirmed = option.kind != SportsMatchKind.broadcaster;
    final action = confirmed ? 'Watch' : 'Open';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SportsFocusPill.row(
        key: ValueKey('sports-details-channel-${channel.url}'),
        label: [
          channel.name,
          if (listing != null) listing.title,
          action,
        ].join(', '),
        height: _rowHeight,
        outlined: !confirmed,
        autofocus: autofocus,
        onPressed: () => _play(channel),
        builder: (_, ink, subtle) => Row(
          children: [
            SportsChannelLogo(name: channel.name, logoUrl: channel.logoUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: sportsLabelText(
                          channel.name,
                          ink,
                          size: 13.5,
                          weight: FontWeight.w600,
                          ellipsize: true,
                        ),
                      ),
                      if (listing != null) ...[
                        const SizedBox(width: 8),
                        sportsLabelText(
                          _timeRange(listing),
                          subtle,
                          size: 11.5,
                          tabular: true,
                        ),
                      ],
                    ],
                  ),
                  sportsLabelText(
                    listing?.title ??
                        (option.kind == SportsMatchKind.channelName
                            ? namedChannelCopy
                            : possibleChannelCopy),
                    subtle,
                    size: 11.5,
                    ellipsize: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            sportsLabelText(action, ink, size: 12.5, weight: FontWeight.w700),
          ],
        ),
      ),
    );
  }

  String _timeRange(SportsGuideListing listing) =>
      '${_timeFormat.format(listing.start.toLocal())}–'
      '${_timeFormat.format(listing.stop.toLocal())}';

  /// Follow targets: one pill per team, or the league for a non-team event.
  List<({String name, String key, bool on, VoidCallback flip})>
  get _followTargets {
    if (_event.isTeamEvent) {
      return [
        for (final team in [_event.home!, _event.away!])
          (
            name: team.shortName,
            key: team.keyIn(_event.leagueId),
            on: _teamKeys.contains(team.keyIn(_event.leagueId)),
            flip: () => _toggleTeam(team),
          ),
      ];
    }
    final id = _event.leagueId;
    return [
      (
        name: _league?.name ?? id,
        key: id,
        on: _leagueIds.contains(id),
        flip: _toggleLeague,
      ),
    ];
  }

  Widget _followButtons({required bool autofocus}) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (index, target) in _followTargets.indexed)
        _followPill(target, autofocus: autofocus && index == 0),
    ],
  );

  Widget _followPill(
    ({String name, String key, bool on, VoidCallback flip}) target, {
    required bool autofocus,
  }) {
    final text = '${target.on ? 'Following' : 'Follow'} ${target.name}';
    return SportsFocusPill.row(
      key: ValueKey('sports-details-follow-${target.key}'),
      label: text,
      selected: target.on,
      autofocus: autofocus,
      onPressed: target.flip,
      builder: (_, ink, _) => Center(
        child: sportsLabelText(
          text,
          ink,
          weight: FontWeight.w700,
          ellipsize: true,
        ),
      ),
    );
  }
}
