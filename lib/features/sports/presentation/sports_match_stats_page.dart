// The match stats page: win probability, team stats, leaders and recent form
// for one match, opened from the board's details panel.
//
// Presentation layer. The page reads [sportsMatchStatsProvider] and tells it
// when polling may run (app in the foreground and this page on top). With
// "hide scores" on, a started match opens behind a reveal step, because every
// section of it gives the result away; nothing is fetched until the viewer
// asks. Back, Escape and the remote's Back close it; focus lands on the
// first section so a D-pad can walk the page from the start.
import 'package:debrify/features/sports/application/sports_match_stats_notifier.dart';
import 'package:debrify/features/sports/data/sports_match_stats_client.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sports_clock.dart';
import 'sports_event_card.dart';
import 'sports_match_stats_sections.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _maxContentWidth = 1100.0;

/// Shown with "hide scores" on, before any match's stats are revealed: a
/// played match's stats give its result away, and even a preview's recent
/// form and records carry other results.
const hiddenStatsCopy =
    'Scores are hidden. Match stats include results, so they stay hidden '
    'until you ask for them.';

const noStatsCopy =
    'No stats for this match yet. They usually appear a day or two before '
    'kick-off.';

const statsErrorCopy = "Couldn't load match stats. Check your connection.";

/// Whether [event] can open the stats page.
bool sportsMatchStatsAvailable(SportsEvent event) =>
    event.isTeamEvent &&
    sportsMatchStatsSupported(sportsLeagueById(event.leagueId));

/// Opens the stats page for [event] over the current route.
Future<void> openSportsMatchStats(
  BuildContext context, {
  required SportsEvent event,
  required bool hideScores,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'sports-match-stats'),
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, _, _) =>
        SportsMatchStatsPage(event: event, hideScores: hideScores),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class SportsMatchStatsPage extends ConsumerStatefulWidget {
  const SportsMatchStatsPage({
    super.key,
    required this.event,
    required this.hideScores,
  });

  final SportsEvent event;
  final bool hideScores;

  @override
  ConsumerState<SportsMatchStatsPage> createState() =>
      _SportsMatchStatsPageState();
}

class _SportsMatchStatsPageState extends ConsumerState<SportsMatchStatsPage>
    with WidgetsBindingObserver {
  late bool _revealed;
  bool _foreground = true;

  SportsEvent get _event => widget.event;

  SportsMatchKey get _key =>
      SportsMatchKey(leagueId: _event.leagueId, eventId: _event.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Not keyed on the match's state: the panel's copy of it can be hours
    // old, and a match it calls scheduled may be over by now.
    _revealed = !widget.hideScores;
    if (_revealed) _wirePolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Inactive is still on screen (a desktop window without focus); only a
    // hidden or paused app stops polling.
    _foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
  }

  /// Polls only while the viewer can see the page.
  void _wirePolling() {
    ref.read(sportsMatchStatsProvider(_key).notifier).canPoll = () =>
        mounted && _foreground && (ModalRoute.of(context)?.isCurrent ?? true);
  }

  void _reveal() {
    setState(() => _revealed = true);
    _wirePolling();
  }

  void _close() => Navigator.of(context).maybePop();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final back =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack;
    if (!back) return KeyEventResult.ignored;
    _close();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final async = _revealed ? ref.watch(sportsMatchStatsProvider(_key)) : null;
    final stats = async?.value;
    final Widget body;
    if (!_revealed) {
      body = _message(
        hiddenStatsCopy,
        action: 'Show match stats',
        key: const ValueKey('sports-stats-reveal'),
        onPressed: _reveal,
      );
    } else if (stats != null) {
      body = stats.hasContent
          ? SportsMatchStatsSections(
              stats: stats,
              sport:
                  sportsLeagueById(_event.leagueId)?.sport ?? SportKind.soccer,
            )
          : _message(
              noStatsCopy,
              action: 'Back',
              key: const ValueKey('sports-stats-empty-back'),
              onPressed: _close,
            );
    } else if ((async?.hasError ?? false) && !(async?.isLoading ?? false)) {
      // Not while a Retry is loading: Riverpod keeps the old error beside
      // the loading flag, and the spinner should show meanwhile.
      body = _message(
        statsErrorCopy,
        action: 'Retry',
        key: const ValueKey('sports-stats-retry'),
        onPressed: () =>
            ref.read(sportsMatchStatsProvider(_key).notifier).refresh(),
      );
    } else {
      body = const Focus(
        // Holds focus while loading so Back works; the first section takes
        // over once it appears.
        autofocus: true,
        child: Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Material(
        color: _tokens.bg,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(stats),
                    const SizedBox(height: 14),
                    _matchup(stats),
                    const SizedBox(height: 18),
                    body,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(SportsMatchStats? stats) {
    final league = sportsLeagueById(_event.leagueId);
    final live = (stats?.status ?? _event.status) == SportsEventStatus.live;
    return Row(
      children: [
        SportsFocusPill.row(
          key: const ValueKey('sports-stats-back'),
          label: 'Back',
          onPressed: _close,
          builder: (_, ink, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 18, color: ink),
              const SizedBox(width: 6),
              sportsLabelText('Back', ink, weight: FontWeight.w700),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: sportsLabelText(
            league?.name ?? _event.leagueId,
            _tokens.accent,
            size: 12,
            weight: FontWeight.w700,
            tracking: 0.7,
            ellipsize: true,
          ),
        ),
        const SizedBox(width: 8),
        if (live && _revealed) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _tokens.rec,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          flex: 2,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: sportsLabelText(
              _statusText(stats),
              _tokens.fgDim,
              size: 12,
              weight: FontWeight.w600,
              ellipsize: true,
            ),
          ),
        ),
      ],
    );
  }

  /// The fresher live clock once stats have loaded; the board's own wording
  /// before that. A hidden played match says only that it was played.
  String _statusText(SportsMatchStats? stats) {
    if (!_revealed) {
      return switch (_event.status) {
        SportsEventStatus.live => 'LIVE',
        SportsEventStatus.finished => 'Played',
        _ => sportsEventStatusText(_event, clock: sportsClock(context)),
      };
    }
    if (stats != null &&
        stats.status != SportsEventStatus.scheduled &&
        stats.statusDetail.isNotEmpty) {
      return stats.statusDetail;
    }
    return sportsEventStatusText(_event, clock: sportsClock(context));
  }

  Widget _matchup(SportsMatchStats? stats) => Column(
    children: [
      _teamRow(_event.home!, stats, stats?.home, _event.homeScore),
      const SizedBox(height: 8),
      _teamRow(_event.away!, stats, stats?.away, _event.awayScore),
    ],
  );

  Widget _teamRow(
    SportsTeam team,
    SportsMatchStats? stats,
    SportsMatchSide? side,
    int? boardScore,
  ) {
    // The feed's score once loaded, but only for a match that kicked off: a
    // postponed one carries a "0" that would read as a 0–0 result.
    final score = !_revealed
        ? null
        : stats == null
        ? boardScore?.toString()
        : (stats.started ? side?.score : null);
    final record = side?.record;
    return Semantics(
      container: true,
      child: Row(
        children: [
          SportsTeamCrest(team: team, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sportsLabelText(
                  team.name,
                  _tokens.fg,
                  size: 17,
                  weight: FontWeight.w700,
                  maxLines: 2,
                  ellipsize: true,
                ),
                if (record != null)
                  sportsLabelText(record, _tokens.fgDim, size: 12),
              ],
            ),
          ),
          if (score != null)
            sportsLabelText(
              score,
              _tokens.fg,
              size: 26,
              weight: FontWeight.w700,
              tabular: true,
            ),
        ],
      ),
    );
  }

  Widget _message(
    String text, {
    String? action,
    Key? key,
    VoidCallback? onPressed,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsLabelText(
        text,
        _tokens.fgMid,
        size: 14,
        height: 1.45,
        maxLines: 12,
        ellipsize: true,
      ),
      if (action != null && onPressed != null) ...[
        const SizedBox(height: 14),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SportsFocusPill.row(
            key: key,
            label: action,
            autofocus: true,
            onPressed: onPressed,
            builder: (_, ink, _) => Center(
              child: sportsLabelText(action, ink, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ],
  );
}

/// The details panel's way in: one row under the matchup.
class SportsMatchStatsButton extends StatelessWidget {
  const SportsMatchStatsButton({
    super.key,
    required this.event,
    required this.hideScores,
  });

  final SportsEvent event;
  final bool hideScores;

  @override
  Widget build(BuildContext context) => SportsFocusPill.row(
    key: const ValueKey('sports-details-stats'),
    label: 'Match stats',
    onPressed: () =>
        openSportsMatchStats(context, event: event, hideScores: hideScores),
    builder: (_, ink, subtle) => Row(
      children: [
        Icon(Icons.insights_rounded, size: 18, color: ink),
        const SizedBox(width: 10),
        Expanded(
          child: sportsLabelText(
            'Match stats',
            ink,
            size: 13.5,
            weight: FontWeight.w600,
            ellipsize: true,
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: subtle),
      ],
    ),
  );
}
